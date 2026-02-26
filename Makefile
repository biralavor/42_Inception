DATA_DIR	:= $(shell grep '^DATA_PATH=' srcs/.env | cut -d'=' -f2)

RED			= \e[0;31m
GREEN		= \e[0;32m
YELLOW		= \e[0;33m
CYAN		= \e[0;36m
RESET		= \e[0m

COMPOSE	= docker compose -f srcs/docker-compose.yml

.PHONY: all
all: dirs
	$(COMPOSE) up -d --build --wait
	@printf "$(GREEN)Inception is up and running!$(RESET)\n"

# Create host volume directories before starting containers
.PHONY: dirs
dirs:
	mkdir -p $(DATA_DIR)/wordpress $(DATA_DIR)/mariadb
	@printf "$(CYAN)Host data directories ready.$(RESET)\n"

# Stop containers, keep volumes and images
.PHONY: down
down:
	$(COMPOSE) down
	@printf "$(YELLOW)Inception stopped.$(RESET)\n"

# Stop + remove containers and networks (keep volumes and images)
.PHONY: clean
clean: down
	docker system prune -f
	@printf "$(YELLOW)Containers and dangling resources removed.$(RESET)\n"

# Full reset: containers + volumes + images + builder cache + host data
# Note: directories are recreated immediately so Docker Desktop's VirtioFS
# has them tracked before the next `make` run attempts to bind-mount them.
.PHONY: fclean
fclean: clean
	docker volume rm $$(docker volume ls -q) 2>/dev/null || true
	docker image rm $$(docker image ls -q) 2>/dev/null || true
	docker builder prune -f 2>/dev/null || true
	sudo rm -rf $(DATA_DIR)
	mkdir -p $(DATA_DIR)/wordpress $(DATA_DIR)/mariadb
	@printf "$(RED)Full clean done.$(RESET)\n"

# Rebuild everything from scratch
.PHONY: re
re: fclean all

# Start mandatory + all bonus services
.PHONY: bonus
bonus: dirs
	BONUS_SETUP=true $(COMPOSE) --profile bonus up -d --build --wait
	@printf "$(GREEN)Inception with bonus services is up!$(RESET)\n"

# Stop bonus services only
.PHONY: bonus_down
bonus_down:
	$(COMPOSE) --profile bonus down
	@printf "$(YELLOW)Bonus services stopped.$(RESET)\n"

# Show container status
.PHONY: ps
ps:
	docker ps -a

# Tail all service logs
.PHONY: logs
logs:
	$(COMPOSE) logs -f

# Run health check
.PHONY: check
check:
	@./InceptionHealthCheck.sh 2>&1 | tee /tmp/inception_check.tmp && sed 's/\x1b\[[0-9;]*m//g' /tmp/inception_check.tmp > release.txt && rm /tmp/inception_check.tmp
