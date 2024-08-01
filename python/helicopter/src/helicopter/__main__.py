import json

import click
from helicopter.helicopter import Helicopter
from loguru import logger


@click.command
@click.option(
    '--output-file-path',
    type=click.Path(),
    help='Path to output JSON file',
    default='cricket_grounds_test_matches_hosted.json',
    show_default=True,
)
@click.option(
    '--save-grounds-data-file-path',
    type=click.Path(resolve_path=True),
    help=(
        'If specified, the scraped grounds data will be stored to the '
        'specified CSV file.'
    ),
    default=None,
    show_default=True,
)
@click.option(
    '--load-grounds-data-file-path',
    type=click.Path(resolve_path=True, exists=True, readable=True),
    help=(
        'If specified, previously saved data from the specified file wiil be loaded '
        'instead of scraping.'
    ),
    default=None,
    show_default=True,
)
def main(
    output_file_path: str,
    save_grounds_data_file_path: str,
    load_grounds_data_file_path: str,
) -> None:
    logger.debug(f'Output file path: {output_file_path}')
    helicopter = Helicopter(
        save_grounds_data_file_path=save_grounds_data_file_path,
        load_grounds_data_file_path=load_grounds_data_file_path,
    )
    cricket_grounds_test_matches_hosted_as_json = (
        helicopter.get_cricket_grounds_test_matches_hosted_data()
    )
    with open(output_file_path, 'w') as file:
        json.dump(cricket_grounds_test_matches_hosted_as_json, file, indent=4)
        logger.info(f'Data saved to {output_file_path}')
