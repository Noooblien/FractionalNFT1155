const { ethers, upgrades } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying from:", deployer.address);

  const uri = "https://example.com/metadata/{id}.json"; // Replace with your actual URI
  const FractionalNFT1155 = await ethers.getContractFactory("FractionalNFT1155");
  const fractionalNFT = await upgrades.deployProxy(FractionalNFT1155, [uri], {
    kind: "uups",
  });
  await fractionalNFT.deployed();
  console.log("FractionalNFT1155 deployed to:", fractionalNFT.address);

  const adminRole = await fractionalNFT.ADMIN_ROLE();
  const hasAdmin = await fractionalNFT.hasRole(adminRole, deployer.address);
  console.log("Deployer has ADMIN_ROLE:", hasAdmin);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});