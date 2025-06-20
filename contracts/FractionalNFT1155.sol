// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;


import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FractionalProperties is ERC1155, Ownable {
    // Mapping to track total fractions per token ID
    mapping(uint256 => uint256) public totalFractions;
    
    // Mapping to store token metadata URIs
    mapping(uint256 => string) private _tokenURIs;
    
    // Event for minting
    event FractionMinted(uint256 indexed tokenId, uint256 amount, string uri);
    
    constructor() ERC1155("") Ownable(msg.sender) {
    }
    
    // Mint function restricted to owner, mints directly to owner
    function mint(
        uint256 tokenId,
        uint256 fractions,
        string memory tokenURI
    ) external onlyOwner {
        require(fractions > 0, "Fractions must be greater than 0");
        require(bytes(tokenURI).length > 0, "URI cannot be empty");
        
        // Update total fractions for this token ID
        totalFractions[tokenId] += fractions;
        
        // Set token URI
        _tokenURIs[tokenId] = tokenURI;
        
        // Mint tokens to owner
        _mint(msg.sender, tokenId, fractions, "");
        
        emit FractionMinted(tokenId, fractions, tokenURI);
    }
    
    // Override transfer functions to make tokens soulbound
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override {
        // Allow minting (from == address(0)) and burning (to == address(0))
        if (from != address(0) && to != address(0)) {
            require(msg.sender == owner(), "Only owner can transfer");
        }
        super._update(from, to, ids, values);
    }
    
    // Get token URI
    function uri(uint256 tokenId) public view override returns (string memory) {
        return _tokenURIs[tokenId];
    }
    
    // Function to get total fractions for a token ID
    function getTotalFractions(uint256 tokenId) external view returns (uint256) {
        return totalFractions[tokenId];
    }
}