module GhcTags.ECTag
  ( module X
  , compareTags
  ) where

import           GhcTags.ECTag.Header    as X
import           GhcTags.ECTag.Parser    as X
import           GhcTags.ECTag.Formatter as X
import           GhcTags.ECTag.Utils     as X

import           GhcTags.Tag (ECTag)
import qualified GhcTags.Tag as Tag

-- | A specialisation of 'GhcTags.Tag.compareTags' to 'ECTag's.
--
compareTags :: ECTag -> ECTag -> Ordering
compareTags = Tag.compareTags
