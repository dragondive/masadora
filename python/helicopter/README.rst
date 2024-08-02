Helicopter
==========

Helicopter is a fun mini-project that provides a prototype for semi-automatically
updating diagrams from external data.

.. contents:: **Table of Contents**

Objective
---------

This project's objective is to scrape data from a website, transform it into a suitable
JSON structure, and then generate diagrams from it using `PlantUML`_.

The prototype uses the Python library `pandas`_ to scrape data from `howstat.com`_
on names and locations of cricket grounds and the number of Test cricket matches hosted
there. It then cleans and transforms the data into JSON format in a hierarchical
structure, that describes the hierarchical location of each cricket ground.

The PlantUML preprocessor reads the JSON file and generates a diagram showing the
hierarchical location, along with a sum of Test cricket matches hosted at each level.

A Github Actions workflow, executed manually from the Github web UI, semi-automates
this process.

Implementation Overview
-----------------------

Scraping Data
~~~~~~~~~~~~~

The data on cricket grounds, their locations and number of Test cricket matches hosted
there is hosted in tabular form on howstat.com at `Grounds List`_. The popular data
analysis library `pandas`_ provides a ``read_html()`` method, which we use to scrape the
table into a ``DataFrame``.

Cleaning Data
~~~~~~~~~~~~~

We perform the following cleaning operations on the scraped data:

1. Remove the words ``Test`` or ``Tests`` from the matches count and then convert the
   number to an integer.
2. Replace the names of some cricket grounds with alternate shorter names. This is done
   only to improve the aesthetics of the diagram generated. It is definitely not meant
   to offend the fans! :relaxed:
3. Replace the names of some cities with alternate names. This is done to remove junk
   from the data or to fix spelling mistakes.

Transforming Data into JSON
~~~~~~~~~~~~~~~~~~~~~~~~~~~

We load the data into a hierarchical structure, schematically described below:

.. code:: console

   All                                          # root of the tree
   ├─ Country 1
   |  ├─ City 1
   |  |  ├─ Ground 1 : matches_count
   |  |  ├─ Ground 2 : matches_count
   |  ├─ Ground 3, City 2 : matches_count       # flatten the last level for cities
   |                                            # with only one cricket ground
   |  ...
   ├─ Country 2
   |  ├─ Ground 1, City 1 : matches_count
   |  ...

We then transform this data into JSON into a recursive structure suitable for our
PlantUML code to generate the diagrams.

Generating PlantUML Diagrams
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

To make this prototype self-contained, my PlantUML code `test_match_wbs_demo.puml`_
from the `plantuml_demo`_ repository is copied over to this repository
`here <https://github.com/dragondive/masadora/blob/main/plantuml/test_match_host_wbs_demo.puml>`_.
This code reads the JSON file data, and draws the hierarchical structure of the cricket
grounds, along with the sum of matches hosted at every level.

The PlantUML code is described in the other repository's document
`Compute and draw Test cricket matches hosting data in hierarchical structure`_.

   \:pencil: **NOTE**

   The PlantUML code in the ``plantuml_demo`` repository is the canonical version.
   Future updates, if any, will usually not be copied over.

Github Actions workflow to semi-automate the process
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The Github Actions workflow `helicopter.yml <https://github.com/dragondive/masadora/blob/main/.github/workflows/helicopter.yml>`_
semi-automates this process. We run this manually from the Github web UI because:

1. Our data source does not send any notification when their data is updated.
2. We can validate the result after every run enabling us to adapt our web scraping and
   cleaning to any changes in layout or data.

The workflow is split into three jobs, suitably named *fly-helicopter*,
*land-helicopter* and *store-helicopter*, which perform the following functions:

1. **fly-helicopter**: Scrape, clean and transform the data into a JSON file.
2. **land-helicopter**: Generate the PlantUML diagram from the JSON file.
3. **store-helicopter**: Commit the diagram, and optionally the intermediate data files,
   to the repository.

Both jobs use the action `actions/cache`_ to speed up the workflow by caching the
installed software and dependencies.

Additional features
~~~~~~~~~~~~~~~~~~~

Helicopter also provides the following additional features:

1. **Save the scraped and cleaned data to CSV file**: The data scraped and cleaned
   could be useful for other purposes. Hence, helicopter enables it to be saved to a
   CSV file.
2. **Load data from CSV file instead of scraping**: The JSON file can be generated from
   a previously saved CSV file, bypassing the scraping and cleaning.

Results
-------

**Generated diagram**

   \:bulb: **TIP**

   The diagram below may not be clearly visible on the Github webpage. You can open it
   in a new tab/window or download it for better clarity. The image is in SVG format,
   allowing you to zoom in for a clearer view.

|Hierarchical representation of Test cricket matches hosted at cricket grounds|

**Scraped data in CSV format**

https://github.com/dragondive/masadora/blob/7167e4ac1fe7351df29a6c41396bc25fbbe6bd0a/python/helicopter/results/cricket_grounds_data.csv#L1-L124

**Generated JSON file**

https://github.com/dragondive/masadora/blob/7167e4ac1fe7351df29a6c41396bc25fbbe6bd0a/python/helicopter/results/cricket_grounds_test_matches_hosted.json#L1-L682

.. _PlantUML: https://plantuml.com/
.. _pandas: https://pandas.pydata.org/
.. _howstat.com: https://www.howstat.com/
.. _Grounds List: https://www.howstat.com/Cricket/Statistics/Grounds/GroundList.asp?Scope=T
.. _test_match_wbs_demo.puml: https://github.com/dragondive/plantuml_demo/blob/33e13848c91b5bc321864b16ec968fa9eeaba080/src/preprocessor/test_match_host_wbs_demo.puml
.. _plantuml_demo: https://github.com/dragondive/plantuml_demo
.. _Compute and draw Test cricket matches hosting data in hierarchical structure: https://github.com/dragondive/plantuml_demo/tree/main/src/preprocessor#compute-and-draw-test-cricket-matches-hosting-data-in-hierarchical-structure
.. _actions/cache: https://github.com/actions/cache

.. |Hierarchical representation of Test cricket matches hosted at cricket grounds| image:: https://github.com/dragondive/masadora/blob/7167e4ac1fe7351df29a6c41396bc25fbbe6bd0a/python/helicopter/results/test_match_host_wbs_demo.svg
