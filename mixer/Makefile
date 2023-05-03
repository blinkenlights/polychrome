protobuf_generate:
	protoc \
		-I../protobuf \
		--elixir_out=./lib/mixer/protobuf \
		--plugin=../protobuf/protoc-gen-elixir \
		--elixir_opt=package_prefix=mixer.protobuf \
		schema.proto

run:
	iex -S mix

