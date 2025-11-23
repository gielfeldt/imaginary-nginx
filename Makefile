.PHONY: test

test:
	@echo "Starting services"
	@docker compose -f docker-compose.test.yml up -d imaginary-test cache-test
	@docker compose -f docker-compose.test.yml run --rm test || test_result=$$?
	@echo "Stopping services"
	@docker compose -f docker-compose.test.yml down
	@exit $${test_result:-0}
