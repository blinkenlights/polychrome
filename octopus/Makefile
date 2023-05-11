protobuf_generate:
	protoc \
		-I../protobuf \
		--elixir_out=./lib/octopus/protobuf \
		--plugin=../protobuf/protoc-gen-elixir \
		--elixir_opt=package_prefix=octopus.protobuf \
		schema.proto

run:
	iex -S mix

