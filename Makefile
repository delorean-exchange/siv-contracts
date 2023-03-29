dlx:
	cp ../dlx/dlx-contracts/json/config.arbitrum.json ./json/dlx-config.arbitrum.json
	cp ../dlx/dlx-contracts/json/config.localhost.json ./json/dlx-config.localhost.json

deploy_fake_localhost: dlx
	NETWORK=localhost forge script script/DeployFakeSelfInsuredVault.s.sol --rpc-url http://127.0.0.1:8545 -vv --broadcast
