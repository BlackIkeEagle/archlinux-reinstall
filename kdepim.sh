#!/bin/bash

sudo pacman -S akonadiconsole akonadi-calendar-tools akonadi-import-wizard grantlee-editor itinerary kaddressbook kalarm kdepim-addons kdepim-runtime kleopatra kmail kmail-account-wizard kontact korganizer mbox-importer pim-data-exporter pim-sieve-editor zanshin postgresql postgresql-old-upgrade --assume-installed mariadb

mkdir -p ~/.config/akonadi
cat <<EOL > ~/.config/akonadi/akonadiserverrc
[%General]
Driver=QPSQL
EOL
