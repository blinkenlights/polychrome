export MIX_TARGET = rpi4
export MIX_ENV = prod

protobuf_generate:
	protoc \
		-I../protobuf \
		--elixir_out=./lib/joystick/protobuf \
		--plugin=../protobuf/protoc-gen-elixir \
		--elixir_opt=package_prefix=joystick.protobuf \
		schema.proto

build: 
	mix deps.get
	mix firmware

burn: build
	mix burn --task complete

upload: build
	mix upload joystick.local

update:
	mix deps.update --all

console:
	ssh joystick.local
