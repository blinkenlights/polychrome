pio_binary = ~/.platformio/penv/bin/platformio # default location for binaries installed by platformio IDE in vscode

protobuf_generate:
	python3 \
		.pio/libdeps/panel_1/Nanopb/generator/nanopb_generator.py \
		--cpp-descriptors \
		-S .cpp \
		-D lib/ProtoBuf/ \
		-I../protobuf \
		schema.proto 

monitor:
	$(pio_binary) device monitor

uart: 
	$(pio_binary) run --target upload -e uart
	
upload: 
	$(pio_binary) run --target upload -e panel_1

upload_all: 
	$(pio_binary) run --target upload -e panel_1 -e panel_2 -e panel_3