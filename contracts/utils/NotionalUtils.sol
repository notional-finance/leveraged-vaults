// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import {Token, TokenType} from "../global/Types.sol";
import {Deployments} from "../global/Deployments.sol";
import {VaultState} from "../global/Types.sol";

// @audit is this really required?
library NotionalUtils {
    function _getNotionalUnderlyingToken(uint16 currencyId) internal view returns (address) {
        (Token memory assetToken, Token memory underlyingToken) = Deployments.NOTIONAL.getCurrency(currencyId);

        return assetToken.tokenType == TokenType.NonMintable ?
            assetToken.tokenAddress : underlyingToken.tokenAddress;
    }
}