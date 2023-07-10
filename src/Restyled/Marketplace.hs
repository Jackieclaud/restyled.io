module Restyled.Marketplace
  ( -- * Data access
    findOrCreateMarketplacePlan
  , fetchUserHasMarketplacePlan

    -- * Checking purchased features
  , MarketplacePlanAllows (..)
  , marketplacePlanAllows
  , MarketplacePlanLimitation (..)
  , isPrivateRepoPlan
  ) where

import Restyled.Prelude

import Restyled.Models
import Restyled.PrivateRepoAllowance
import Restyled.PrivateRepoEnabled

-- | Find or create a 'MarketplacePlan' by its @GitHubId@/@Name@
findOrCreateMarketplacePlan
  :: MonadIO m => MarketplacePlan -> SqlPersistT m (Entity MarketplacePlan)
findOrCreateMarketplacePlan plan@MarketplacePlan {..} = do
  -- Unsafe UPSERT required because github_id is a nullable index. Should be
  -- fine since we always expect this to exist.
  mPlan <-
    selectFirst
      [ MarketplacePlanGithubId ==. marketplacePlanGithubId
      , MarketplacePlanName ==. marketplacePlanName
      ]
      []
  maybe (insertEntity plan) pure mPlan

fetchUserHasMarketplacePlan
  :: MonadIO m => MarketplacePlanId -> GitHubUserName -> SqlPersistT m Bool
fetchUserHasMarketplacePlan planId login =
  exists
    [ MarketplaceAccountMarketplacePlan ==. planId
    , MarketplaceAccountGithubLogin ==. login
    ]

data MarketplacePlanAllows
  = MarketplacePlanAllows (Maybe MarketplacePlan)
  | MarketplacePlanForbids MarketplacePlanLimitation
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

data MarketplacePlanLimitation
  = MarketplacePlanNotFound
  | MarketplacePlanPublicOnly
  | MarketplacePlanMaxRepos
  | MarketplacePlanAccountExpired UTCTime
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

marketplacePlanAllows
  :: MonadIO m => Entity Repo -> SqlPersistT m MarketplacePlanAllows
marketplacePlanAllows repo@(Entity _ Repo {..})
  | repoIsPrivate = marketplacePlanAllowsPrivate repo
  | otherwise = pure $ MarketplacePlanAllows Nothing

marketplacePlanAllowsPrivate
  :: MonadIO m => Entity Repo -> SqlPersistT m MarketplacePlanAllows
marketplacePlanAllowsPrivate repo = do
  mEnabled <- enableMarketplaceRepo repo

  pure $ case mEnabled of
    Nothing -> MarketplacePlanForbids MarketplacePlanNotFound
    Just (PrivateRepoEnabled plan) -> MarketplacePlanAllows $ Just plan
    Just PrivateRepoNotAllowed ->
      MarketplacePlanForbids MarketplacePlanPublicOnly
    Just PrivateRepoLimited ->
      MarketplacePlanForbids MarketplacePlanMaxRepos
    Just (PrivateRepoAccountExpired expiredAt) ->
      MarketplacePlanForbids $ MarketplacePlanAccountExpired expiredAt

isPrivateRepoPlan :: MarketplacePlan -> Bool
isPrivateRepoPlan MarketplacePlan {..} =
  case marketplacePlanPrivateRepoAllowance of
    PrivateRepoAllowanceNone -> False
    PrivateRepoAllowanceUnlimited -> True
    PrivateRepoAllowanceLimited _ -> True
