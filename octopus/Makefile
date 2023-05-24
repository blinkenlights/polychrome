run:
	iex -S mix phx.server

protobuf_generate:
	protoc \
		-I../protobuf \
		--elixir_out=./lib/octopus/protobuf \
		--plugin=../protobuf/protoc-gen-elixir \
		--elixir_opt=package_prefix=octopus.protobuf \
		schema.proto

deploy:
	fly deploy

remote-shell:
	fly ssh console --pty -C "/app/bin/octopus remote"
