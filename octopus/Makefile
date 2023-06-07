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
	rsync -av --delete --filter=':- .gitignore' . oldie:octopus
	ssh oldie "cd octopus && make release"
	ssh oldie "sudo systemctl restart octopus"

remote-shell:
	fly ssh console --pty -C "/app/bin/octopus remote"
