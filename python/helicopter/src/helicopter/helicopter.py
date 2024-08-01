import os
from collections import OrderedDict
from io import StringIO

import pandas
import pandas.core
import pandas.core.series
import requests
from loguru import logger
from pandas.errors import ParserError
from requests.exceptions import RequestException


class Helicopter:
    def __init__(
        self,
        save_grounds_data_file_path: str = None,
        load_grounds_data_file_path: str = None,
    ):
        self.save_grounds_data_file_path: str = save_grounds_data_file_path
        self.load_grounds_data_file_path: str = load_grounds_data_file_path

    def get_cricket_grounds_test_matches_hosted_data(self) -> OrderedDict:
        if self.load_grounds_data_file_path:
            logger.info(
                f"Loading grounds data from file {self.load_grounds_data_file_path}"
            )
            grounds_data: pandas.DataFrame = pandas.read_csv(
                self.load_grounds_data_file_path
            )
        else:
            logger.info(
                f"Scraping grounds data from url {Helicopter.HOWSTAT_GROUNDS_URL}"
            )
            grounds_data = self._scrape_grounds_data()
            self._clean_grounds_data(grounds_data)

            if self.save_grounds_data_file_path:
                grounds_data.to_csv(self.save_grounds_data_file_path, index=False)
                logger.info(f"Grounds data saved to {self.save_grounds_data_file_path}")

        tests_hosting_data: OrderedDict = OrderedDict({'name': 'All', 'list': []})
        grounds_data.apply(
            self._update_tests_hosting_data, args=(tests_hosting_data,), axis=1
        )
        self._flatten_city_ground_list(tests_hosting_data)

        return tests_hosting_data

    def _scrape_grounds_data(self) -> pandas.DataFrame | None:
        try:
            response: requests.Response = requests.get(
                Helicopter.HOWSTAT_GROUNDS_URL, headers={}, timeout=30
            )
            response.raise_for_status()
        except RequestException as e:
            logger.error(
                f"Scraping request to '{Helicopter.HOWSTAT_GROUNDS_URL}' "
                f"failed with error: {e}"
            )
            return None

        html: str = response.text
        logger.debug(f"Scraped HTML: {html}")

        try:
            tables: list[pandas.DataFrame] = pandas.read_html(StringIO(html))
        except (ParserError, ValueError) as e:
            logger.error(f"Parsing HTML failed with error: {e}")
            return None

        try:
            data: pandas.DataFrame = tables[Helicopter.GROUNDS_DATA_POSITION_IN_SCRAPED_TABLES_LIST]
            logger.debug(f"Scraped grounds data: {data}")

            # The response has column names in the first row, so we use it to rename
            # the columns. The last 3 columns all have the name 'Profile & Statistics'
            # in the response, so we override the names to 'Tests', 'ODIs', and 'T20s'.
            data.columns = list(data.iloc[0][0:3]) + ["Tests", "ODIs", "T20s"]

            # Remove the first row (which contains column names)
            # and the last row (which is a summary row having total number of grounds)
            data = data.iloc[1:-1]
            data.reset_index(drop=True, inplace=True)
            return data
        except (IndexError, KeyError) as e:
            logger.error(f"Error while scraping grounds data: {e}")
            return None

    def _clean_grounds_data(self, data: pandas.DataFrame) -> None:
        def _match_count_to_int():
            # Replace NaN with string '0', not integer 0, to prevent exceptions
            # with the `.str` invocations below. The `.astype(int)` would convert them
            # to integer 0 anyway.
            data.fillna('0', inplace=True)

            data['Tests'] = (
                data['Tests'].str.replace(r' Test(s)?', '', regex=True).astype(int)
            )
            data['ODIs'] = (
                data['ODIs'].str.replace(r' ODI(s)?', '', regex=True).astype(int)
            )
            data['T20s'] = (
                data['T20s'].str.replace(r' T20(s)?', '', regex=True).astype(int)
            )
            logger.debug(f"Cleaned grounds data")

        _match_count_to_int()

        def _replace_ground_names():
            replace_dict = (
                pandas.read_csv(
                    os.path.join(
                        os.path.dirname(__file__), 'data', 'replace_ground_names.csv'
                    )
                )
                .set_index('name_in_data')['alternate_name']
                .to_dict()
            )
            data.replace(replace_dict, inplace=True)
            logger.debug(f"Replaced ground names")

        _replace_ground_names()

        def _replace_city_names():
            replace_dict = (
                pandas.read_csv(
                    os.path.join(
                        os.path.dirname(__file__), 'data', 'replace_city_names.csv'
                    )
                )
                .set_index('name_in_data')['alternate_name']
                .to_dict()
            )
            data.replace(replace_dict, inplace=True)
            logger.debug(f"Replaced city names")

        _replace_city_names()

    def _update_tests_hosting_data(
        self, row: pandas.core.series.Series, data_dict: OrderedDict
    ) -> None:
        # Check if the country already exists in the list. If not, create a new one.
        # In either case, use that country item from the list to update the city and
        # ground data below.
        try:
            country_item = next(
                item for item in data_dict['list'] if item['name'] == row['Country']
            )
            logger.debug(f"Found country: {row['Country']}")
        except StopIteration:
            data_dict['list'].append(OrderedDict({'name': row['Country'], 'list': []}))
            country_item = data_dict['list'][-1]
            logger.info(f"Added new country: {row['Country']} to the list")

        # Similarly, add a new city item to the country list or use the existing one.
        try:
            city_item = next(
                item for item in country_item['list'] if item['name'] == row['City']
            )
            logger.debug(f"Found city: {row['City']}")
        except StopIteration:
            country_item['list'].append(OrderedDict({'name': row['City'], 'list': []}))
            city_item = country_item['list'][-1]
            logger.info(
                f"Added new city: {row['City']} to the list of {row['Country']}"
            )

        # Now add the ground and matches count to the city list.
        city_item['list'].append(
            OrderedDict({'name': row['Ground'], 'count': row['Tests']})
        )
        logger.info(
            f"Added ground: {row['Ground']} to the list of {row['City']} "
            f"with count: {row['Tests']}"
        )

    def _flatten_city_ground_list(self, data_dict: OrderedDict) -> None:
        # Multiple grounds in a single city are much less common than one ground in
        # a city. Hence, for the common case, we flatten one level of hierarchy by
        # combining the ground name with the city name.
        for country in data_dict['list']:
            for city in country['list']:
                if len(city['list']) == 1:
                    city['name'] = f"{city['list'][0]['name']}, {city['name']}"
                    city['count'] = city['list'][0]['count']
                    del city['list']
                    logger.debug(
                        f"Flattened data for {city['name']} in {country['name']}"
                    )
                else:
                    logger.debug(
                        f"More than one ground in {city['name']} in {country['name']}"
                    )

    HOWSTAT_GROUNDS_URL: str = (
        'https://www.howstat.com/Cricket/Statistics/Grounds/GroundList.asp?Scope=T'
    )
    GROUNDS_DATA_POSITION_IN_SCRAPED_TABLES_LIST: int = (
        3  # Grounds data is the table at index 3 in the HTML response
    )
