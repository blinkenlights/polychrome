oldie_hostname = 192.168.23.12

run:
	iex -S mix phx.server

protobuf_generate:
	protoc \
		-I../protobuf \
		--elixir_out=./lib/octopus/protobuf \
		--plugin=../protobuf/protoc-gen-elixir \
		--elixir_opt=package_prefix=octopus.protobuf \
		schema.proto

release: export MIX_ENV=prod
release:
	mix setup
	mix assets.deploy
	mix release --overwrite

deploy-fly:
	fly deploy

deploy-oldie:
	rsync -rl --delete --filter=':- .gitignore' --perms . $(oldie_hostname):/opt/octopus
	ssh $(oldie_hostname) "user=$$(whoami); sudo chown -R $$user:$$user /opt/octopus"
	ssh $(oldie_hostname) "cd /opt/octopus && make release"
	ssh $(oldie_hostname) "sudo chown -R octopus:octopus /opt/octopus"
	ssh $(oldie_hostname) "sudo chmod -R 775 /opt/octopus"
	ssh $(oldie_hostname) "sudo systemctl restart octopus.service"

remote-shell:
	fly ssh console --pty -C "/app/bin/octopus remote"
