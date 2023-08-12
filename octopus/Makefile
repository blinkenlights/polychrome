oldie_hostname =  oldie.taila332c.ts.net

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
	rsync -rl --delete --filter=':- .gitignore' . $(oldie_hostname):octopus
	ssh $(oldie_hostname) "cd octopus && make release"
	ssh $(oldie_hostname) "sudo rsync -r octopus/_build/prod/rel/octopus /opt"
	ssh $(oldie_hostname) "sudo systemctl restart octopus.service"

remote-shell:
	fly ssh console --pty -C "/app/bin/octopus remote"
