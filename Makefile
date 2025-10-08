TERRAFORM_DOCS_VERSION ?= 0.20.0
TERRAFORM_TF_LINT_VERSION ?= 0.59.1
TERRAFORM_TF_SEC_VERSION ?= 1.28.14
.PHONY: lint tfscan generate-docs

lint:
	docker run --rm -v $${PWD}:/data -t ghcr.io/terraform-linters/tflint:v$(TERRAFORM_TF_LINT_VERSION) --var-file=/data/examples/test.tfvars
tfsec:
	docker run --rm -it -v "$$(pwd):/src" aquasec/tfsec:v$(TERRAFORM_TF_SEC_VERSION) /src --tfvars-file=/src/examples/test.tfvars

generate-docs: lint
	docker run --rm -u $$(id -u) \
		--volume "$(PWD):/terraform-docs" \
		-w /terraform-docs \
		quay.io/terraform-docs/terraform-docs:$(TERRAFORM_DOCS_VERSION) markdown table --config .terraform-docs.yml --output-file README.md --output-mode inject .
