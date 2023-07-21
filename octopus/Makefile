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
	rsync -rl --delete --filter=':- .gitignore' --perms --chmod=775 . oldie.taila332c.ts.net:/opt/octopus
	ssh oldie.taila332c.ts.net "user=$$(whoami); sudo chown -R $$user:$$user /opt/octopus"
	ssh oldie.taila332c.ts.net "cd /opt/octopus && make release"
	ssh oldie.taila332c.ts.net "sudo chown -R octopus:octopus /opt/octopus"
	ssh oldie.taila332c.ts.net "sudo chmod -R 775 /opt/octopus"
	ssh oldie.taila332c.ts.net "sudo systemctl restart octopus.service"

remote-shell:
	fly ssh console --pty -C "/app/bin/octopus remote"
