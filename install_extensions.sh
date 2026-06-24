#!/usr/bin/env bash
set -euo pipefail

source /usr/lib/ckan/default/bin/activate

gh auth setup-git

pip install ckanext-envvars@git+https://github.com/okfn/ckanext-envvars@v0.0.6

pip install ckanext-spatial@git+https://github.com/dathere/ckanext-spatial.git@gztr
curl -fsSL https://raw.githubusercontent.com/dathere/ckanext-spatial/gztr/requirements.txt | pip install -r /dev/stdin

git clone https://github.com/dathere/dathere_theme.git -b sandbox /usr/lib/ckan/default/src/dathere_theme
pip install -e /usr/lib/ckan/default/src/dathere_theme
pip install -r /usr/lib/ckan/default/src/dathere_theme/requirements.txt

git clone https://github.com/dathere/ckanext-gztr.git -b geoconnex /usr/lib/ckan/default/src/ckanext-gztr
pip install -e /usr/lib/ckan/default/src/ckanext-gztr
pip install -r /usr/lib/ckan/default/src/ckanext-gztr/requirements.txt

pip install setuptools==70.0.0
