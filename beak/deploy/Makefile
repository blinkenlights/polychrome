SHELL := /bin/bash

host=all
tags=all
inventory=hosts
ansible_run=ansible-playbook playbook.yml -i "$(inventory)" --limit "$(host)" --tags "$(tags)"

install:
	ansible-galaxy install --force -r requirements.yml
a_setup: tags=setup
a_setup: 
	$(ansible_run) --diff
a_deploy: tags=deploy
a_deploy:
	$(ansible_run) --diff
	
