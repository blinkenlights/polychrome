oldie_hostname = oldie@oldie.mule-nunki.ts.net

run:
	iex -S mix phx.server

protobuf_generate:
	protoc \
		-I../protobuf \
		--elixir_out=./lib \
		--plugin=../protobuf/protoc-gen-elixir \
		--elixir_opt=package_prefix=octopus.protobuf \
		schema.proto

release: export MIX_ENV=prod
release:
	mix setup
	mix assets.deploy
	mix release --overwrite

deploy-fly:
	fly deploy --config deploy/fly/fly.toml

deploy-oldie:
	rsync -rlv --delete --filter=':- .gitignore' --exclude='_build' --exclude='deps' --exclude='priv/native' --exclude='native/target' --exclude='native/octopus_webp/target' . ${oldie_hostname}:/opt/octopus
	ssh ${oldie_hostname} "sudo systemctl restart octopus.service"

deploy-metaebene:
	./deploy/metaebene/deploy.sh

deploy-redlady:
	./deploy/redlady/deploy.sh

deploy-gravity:
	./deploy/gravity/deploy.sh

monitor-redlady:
	ssh tim@redlady.crested-frog.ts.net "cd /home/tim/polychrome/deploy/redlady && docker compose logs -f"

monitor-gravity:
	ssh tim@gravity.crested-frog.ts.net "cd /home/tim/polychrome/deploy/gravity && docker compose logs -f"

build-polychrome-image: export MIX_ENV=prod
build-polychrome-image:
	mkdir -p $(HOME)/.cache/polychrome-docker
	@if ! docker buildx inspect polychrome-cache >/dev/null 2>&1; then \
		docker buildx create --name polychrome-cache --driver docker-container --bootstrap; \
	fi
	docker buildx use polychrome-cache
	docker buildx build \
		--load \
		--cache-from type=local,src=$(HOME)/.cache/polychrome-docker \
		--cache-to type=local,dest=$(HOME)/.cache/polychrome-docker,mode=max \
		-t polychrome:latest -f Dockerfile .
	docker save polychrome:latest | gzip > /tmp/polychrome-latest.tar.gz

deploy-metaebene-skip-build:
	./deploy/metaebene/deploy.sh --skip-build

deploy-redlady-skip-build:
	./deploy/redlady/deploy.sh --skip-build

deploy-gravity-skip-build:
	./deploy/gravity/deploy.sh --skip-build

remote-logs:
	ssh ${oldie_hostname} "sudo journalctl -u octopus.service -f"

remote-shell:
	fly ssh console --pty -C "/app/bin/octopus remote"
