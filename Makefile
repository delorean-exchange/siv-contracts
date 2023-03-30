RPC_URL=https://arb-mainnet.g.alchemy.com/v2/0R0ziU-Vo3g37WxX7ItzFOnL3doOIPh1

dlx:
	cp ../dlx/dlx-contracts/json/config.arbitrum.json ./json/dlx-config.arbitrum.json
	cp ../dlx/dlx-contracts/json/config.localhost.json ./json/dlx-config.localhost.json

fake_localhost: deploy_fake_localhost
fake_arbitrum: deploy_fake_arbitrum

deploy_fake_localhost: dlx
	NETWORK=localhost forge script script/DeployFakeSelfInsuredVault.s.sol --rpc-url http://127.0.0.1:8545 -vv --broadcast
	python3 python/consolidate_config.py
deploy_fake_arbitrum: dlx
	NETWORK=arbitrum forge script script/DeployFakeSelfInsuredVault.s.sol --rpc-url $(RPC_URL) -vv --broadcast
	python3 python/consolidate_config.py
