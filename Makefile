FARD_SRC ?= $(HOME)/Downloads/FARD_v0.5
IMAGE_NAME ?= qasim
IMAGE_TAG ?= latest

.PHONY: docker-build docker-run docker-clean run test

docker-build:
@echo "Copying FARD source..."
@rm -rf fard_src
@cp -r $(FARD_SRC) fard_src
@echo "Building Docker image..."
docker build -t $(IMAGE_NAME):$(IMAGE_TAG) .
@rm -rf fard_src

docker-run:
docker run -d \
--name qasim \
-p 9801:9801 \
-e QASIM_CHAIN_SECRET_HEX=$$(openssl rand -hex 32) \
-v qasim-data:/data \
$(IMAGE_NAME):$(IMAGE_TAG)

docker-stop:
docker stop qasim && docker rm qasim

docker-clean:
docker rmi $(IMAGE_NAME):$(IMAGE_TAG)
rm -rf fard_src

run:
QASIM_CHAIN_SECRET_HEX=$$(openssl rand -hex 32) \
fardrun run --program main.fard --out /tmp/qasim

test:
fardrun test --program tests/test_qasim_objects.fard
fardrun test --program tests/test_qasim_objects_model.fard
fardrun test --program tests/test_qasim_prices.fard
fardrun test --program tests/test_qasim_state.fard
