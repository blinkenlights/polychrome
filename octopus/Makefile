oldie_hostname =  oldie.tail7e11c.ts.net

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
	rsync -rlv --delete --filter=':- .gitignore' . $(oldie_hostname):/opt/octopus
	ssh $(oldie_hostname) "sudo systemctl restart octopus.service"

remote-shell:
	fly ssh console --pty -C "/app/bin/octopus remote"
