DATA_DIR	= /home/umeneses/data

RED			= \e[0;31m
GREEN		= \e[0;32m
YELLOW		= \e[0;33m
CYAN		= \e[0;36m
RESET		= \e[0m

.PHONY: all
all: dirs
	docker compose up -d --build
	@printf "$(GREEN)Inception is up and running!$(RESET)\n"

# Create host volume directories before starting containers
.PHONY: dirs
dirs:
	@mkdir -p $(DATA_DIR)/wordpress $(DATA_DIR)/mariadb
	@printf "$(CYAN)Host data directories ready.$(RESET)\n"

# Stop containers, keep volumes and images
.PHONY: down
down:
	docker compose down
	@printf "$(YELLOW)Inception stopped.$(RESET)\n"

# Stop + remove containers and networks (keep volumes and images)
.PHONY: clean
clean: down
	docker system prune -f
	@printf "$(YELLOW)Containers and dangling resources removed.$(RESET)\n"

# Full reset: containers + volumes + images + host data
.PHONY: fclean
fclean: clean
	docker volume rm $$(docker volume ls -q) 2>/dev/null || true
	docker image rm $$(docker image ls -q) 2>/dev/null || true
	sudo rm -rf $(DATA_DIR)
	@printf "$(RED)Full clean done.$(RESET)\n"

# Rebuild everything from scratch
.PHONY: re
re: fclean all

# Show container status
.PHONY: ps
ps:
	docker ps -a

# Tail all service logs
.PHONY: logs
logs:
	docker compose logs -f

# Run health check
.PHONY: check
check:
	@bash InceptionHealthCheck.sh
