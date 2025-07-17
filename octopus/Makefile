oldie_hostname = oldie@oldie.mule-nunki.ts.net

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
	rsync -rlv --delete --filter=':- .gitignore' --exclude='_build' --exclude='deps' --exclude='priv/native' --exclude='native/target' --exclude='native/octopus_webp/target' . ${oldie_hostname}:/opt/octopus
	ssh ${oldie_hostname} "sudo systemctl restart octopus.service"

remote-logs:
	ssh ${oldie_hostname} "sudo journalctl -u octopus.service -f"

remote-shell:
	fly ssh console --pty -C "/app/bin/octopus remote"
