{-# LANGUAGE RecordWildCards #-}

-- | A type for result of parsing.
module Ormolu.Parser.Result
  ( SourceSnippet (..),
    ParseResult (..),
  )
where

import Data.Text (Text)
import GHC.Data.EnumSet (EnumSet)
import GHC.Hs
import GHC.LanguageExtensions.Type
import GHC.Types.SrcLoc
import Ormolu.Parser.Anns
import Ormolu.Parser.CommentStream
import Ormolu.Parser.Pragma (Pragma)

-- | Either a 'ParseResult', or a raw snippet.
data SourceSnippet = RawSnippet Text | ParsedSnippet ParseResult

-- | A collection of data that represents a parsed module in Ormolu.
data ParseResult = ParseResult
  { -- | 'ParsedSource' from GHC
    prParsedSource :: HsModule,
    -- | Ormolu-specfic representation of annotations
    prAnns :: Anns,
    -- | Stack header
    prStackHeader :: Maybe (RealLocated Comment),
    -- | Pragmas and the associated comments
    prPragmas :: [([RealLocated Comment], Pragma)],
    -- | Comment stream
    prCommentStream :: CommentStream,
    -- | Whether or not record dot syntax is enabled
    prUseRecordDot :: Bool,
    -- | Enabled extensions
    prExtensions :: EnumSet Extension,
    -- | Indentation level, can be non-zero in case of region formatting
    prIndent :: Int
  }
