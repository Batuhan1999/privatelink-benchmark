.PHONY: test check fmt build build-linux infra-init infra-plan infra-apply infra-destroy deploy run run-payloads fetch

test:
	go test ./...

check:
	@test -z "$$(gofmt -l ./cmd ./internal)" || (gofmt -l ./cmd ./internal && exit 1)
	go test ./...
	go vet ./...
	terraform -chdir=infra fmt -check
	terraform -chdir=infra validate

fmt:
	gofmt -w ./cmd ./internal
	terraform -chdir=infra fmt

build:
	go build ./cmd/benchmark ./cmd/analyze

build-linux:
	mkdir -p bin
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -o bin/benchmark-linux-arm64 ./cmd/benchmark
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -o bin/analyze-linux-arm64 ./cmd/analyze

infra-init:
	terraform -chdir=infra init

infra-plan:
	terraform -chdir=infra plan -out=benchmark.tfplan

infra-apply:
	terraform -chdir=infra apply benchmark.tfplan

infra-destroy:
	terraform -chdir=infra destroy

deploy:
	./scripts/deploy.sh

run:
	./scripts/run-remote.sh

run-payloads:
	./scripts/run-payload-matrix-remote.sh

fetch:
	./scripts/fetch-results.sh
