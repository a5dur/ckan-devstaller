#!/usr/bin/env bash
set -euo pipefail

source /usr/lib/ckan/default/bin/activate

gh auth setup-git

pip install ckanext-envvars@git+https://github.com/okfn/ckanext-envvars@v0.0.6

pip install ckanext-spatial@git+https://github.com/dathere/ckanext-spatial.git@gztr
curl -fsSL https://raw.githubusercontent.com/dathere/ckanext-spatial/gztr/requirements.txt | pip install -r /dev/stdin

sudo rm -rf /usr/lib/ckan/default/src/dathere_theme
git clone https://github.com/dathere/dathere_theme.git -b sandbox /usr/lib/ckan/default/src/dathere_theme
pip install -e /usr/lib/ckan/default/src/dathere_theme
pip install -r /usr/lib/ckan/default/src/dathere_theme/requirements.txt

sudo rm -rf /usr/lib/ckan/default/src/ckanext-gztr
git clone https://github.com/dathere/ckanext-gztr.git -b sandbox /usr/lib/ckan/default/src/ckanext-gztr
pip install -e /usr/lib/ckan/default/src/ckanext-gztr
pip install -r /usr/lib/ckan/default/src/ckanext-gztr/requirements.txt

pip install setuptools==70.0.0

# Enable all extension plugins. Order is deliberate (issue dathere/datapusher-plus#331):
# datapusher_plus MUST precede scheming_datasets so DPP's scheming form_snippet overrides
# (suggestion buttons) win the template-priority race under IConfigurer reverse iteration.
# Do NOT set extra_template_paths — it caused a RecursionError in that setup.
ckan config-tool /etc/ckan/default/ckan.ini -s app:main \
  ckan.plugins="envvars activity datastore datapusher_plus scheming_datasets spatial_metadata spatial_query dathere_theme dathere_custom_css dathere_custom_homepage dathere_custom_header dathere_custom_footer gztr"

# gztr dataset.yaml carries the DRUF suggestion_formula fields. Without scheming.dataset_schemas
# there is no schema for type 'dataset', so the DRUF add_dataset snippet renders no buttons.
ckan config-tool /etc/ckan/default/ckan.ini -s app:main scheming.dataset_schemas=ckanext.gztr:schemas/dataset.yaml
ckan config-tool /etc/ckan/default/ckan.ini -s app:main \
  scheming.presets="ckanext.scheming:presets.json ckanext.gztr:schemas/presets.yaml"
