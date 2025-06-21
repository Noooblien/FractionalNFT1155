// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FractionalProperties is ERC1155, Ownable {
    // Mapping to track total fractions per token ID
    mapping(uint256 => uint256) public totalFractions;
    
    // Mapping to store token metadata URIs
    mapping(uint256 => string) private _tokenURIs;
    
    // Mapping to track if a token ID has been minted
    mapping(uint256 => bool) private _tokenMinted;
    
    // Address of the approver for transfers
    address public transferApprover;
    
    // Mapping to store transfer approvals (tokenId => to => fractions)
    mapping(uint256 => mapping(address => uint256)) private _transferApprovals;
    
    // Event for minting
    event FractionMinted(uint256 indexed tokenId, uint256 amount, string uri);
    
    // Event for transfer approval
    event TransferApproved(uint256 indexed tokenId, address indexed to, uint256 fractions, address indexed approver);
    
    // Event for setting transfer approver
    
    constructor() ERC1155("") Ownable(msg.sender) {
        
    }
    

    
    // Mint function restricted to owner, mints directly to owner
    function mint(
        uint256 tokenId,
        uint256 fractions,
        string memory tokenURI
    ) external onlyOwner {
        require(!_tokenMinted[tokenId], "Token ID already minted");
        require(fractions > 0, "Fractions must be greater than 0");
        require(bytes(tokenURI).length > 0, "URI cannot be empty");
        
        // Mark token ID as minted
        _tokenMinted[tokenId] = true;
        
        // Update total fractions for this token ID
        totalFractions[tokenId] += fractions;
        
        // Set token URI
        _tokenURIs[tokenId] = tokenURI;
        
        // Mint tokens to owner
        _mint(msg.sender, tokenId, fractions, "");
        
        emit FractionMinted(tokenId, fractions, tokenURI);
    }
    
    // Approver approves a transfer with specific number of fractions
    function approveTransfer(uint256 tokenId, address to, uint256 fractions) external {
        require(to != address(0), "Cannot approve to zero address");
        require(fractions > 0, "Fractions must be greater than 0");
        require(fractions <= totalFractions[tokenId], "Approved fractions exceed total fractions");
        _transferApprovals[tokenId][to] = fractions;
        emit TransferApproved(tokenId, to, fractions, msg.sender);
    }
    
    // Override transfer functions to make tokens soulbound with approval
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override {
        // Allow minting (from == address(0)) and burning (to == address(0))
        if (from != address(0) && to != address(0)) {
            require(msg.sender == owner(), "Only owner can transfer");
            for (uint256 i = 0; i < ids.length; i++) {
                require(_transferApprovals[ids[i]][to] >= values[i], "Insufficient approved fractions");
                // Reduce approval by the transferred amount
                _transferApprovals[ids[i]][to] -= values[i];
            }
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
    
    // Function to check if token ID is minted
    function isTokenMinted(uint256 tokenId) external view returns (bool) {
        return _tokenMinted[tokenId];
    }
    
    // Function to check transfer approval
    function getApprovedFractions(uint256 tokenId, address to) external view returns (uint256) {
        return _transferApprovals[tokenId][to];
    }
}