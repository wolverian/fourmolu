{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

-- | Rendering of import and export lists.
module Ormolu.Printer.Meat.ImportExport
  ( p_hsmodExports,
    p_hsmodImport,
    breakIfNotDiffFriendly,
  )
where

import Control.Monad
import qualified Data.Text as T
import GHC.Hs.Extension
import GHC.Hs.ImpExp
import GHC.LanguageExtensions.Type
import GHC.Types.SrcLoc
import GHC.Unit.Types
import Ormolu.Config (poDiffFriendlyImportExport)
import Ormolu.Config (CommaStyle (..), PrinterOpts (poIECommaStyle), poDiffFriendlyImportExport)
import Ormolu.Printer.Combinators
import Ormolu.Printer.Meat.Common
import Ormolu.Utils (RelativePos (..), attachRelativePos)

p_hsmodExports :: [LIE GhcPs] -> R ()
p_hsmodExports [] = do
  txt "("
  breakpoint'
  txt ")"
p_hsmodExports xs =
  parens' False $ do
    layout <- getLayout
    commaStyle <- getPrinterOpt poIECommaStyle
    sep
      breakpoint
      (\(p, l) -> sitcc (located l (p_lie layout p commaStyle)))
      (attachRelativePos' xs)

p_hsmodImport :: ImportDecl GhcPs -> R ()
p_hsmodImport ImportDecl {..} = do
  useQualifiedPost <- isExtensionEnabled ImportQualifiedPost
  txt "import"
  space
  when (ideclSource == IsBoot) (txt "{-# SOURCE #-}")
  space
  when ideclSafe (txt "safe")
  space
  when
    (isImportDeclQualified ideclQualified && not useQualifiedPost)
    (txt "qualified")
  space
  case ideclPkgQual of
    Nothing -> return ()
    Just slit -> atom slit
  space
  inci $ do
    located ideclName atom
    when
      (isImportDeclQualified ideclQualified && useQualifiedPost)
      (space >> txt "qualified")
    case ideclAs of
      Nothing -> return ()
      Just l -> do
        space
        txt "as"
        space
        located l atom
    space
    case ideclHiding of
      Nothing -> return ()
      Just (hiding, _) ->
        when hiding (txt "hiding")
    case ideclHiding of
      Nothing -> return ()
      Just (_, L _ xs) -> do
        breakIfNotDiffFriendly
        parens' True $ do
          layout <- getLayout
          commaStyle <- getPrinterOpt poIECommaStyle
          sep
            breakpoint
            (\(p, l) -> sitcc (located l (p_lie layout p commaStyle)))
            (attachRelativePos xs)
    newline

p_lie :: Layout -> RelativePos -> CommaStyle -> IE GhcPs -> R ()
p_lie encLayout relativePos commaStyle = \case
  IEVar NoExtField l1 ->
    withComma $
      located l1 p_ieWrappedName
  IEThingAbs NoExtField l1 ->
    withComma $
      located l1 p_ieWrappedName
  IEThingAll NoExtField l1 -> withComma $ do
    located l1 p_ieWrappedName
    space
    txt "(..)"
  IEThingWith NoExtField l1 w xs _ -> sitcc $
    withComma $ do
      located l1 p_ieWrappedName
      breakIfNotDiffFriendly
      inci $ do
        let names :: [R ()]
            names = located' p_ieWrappedName <$> xs
        parens' False . sep commaDel' sitcc $
          case w of
            NoIEWildcard -> names
            IEWildcard n ->
              let (before, after) = splitAt n names
               in before ++ [txt ".."] ++ after
  IEModuleContents NoExtField l1 -> withComma $ do
    located l1 p_hsmodName
  IEGroup NoExtField n str -> do
    case relativePos of
      SinglePos -> return ()
      FirstPos -> return ()
      MiddlePos -> newline
      LastPos -> newline
    p_hsDocString (Asterisk n) False (noLoc str)
  IEDoc NoExtField str ->
    p_hsDocString Pipe False (noLoc str)
  IEDocNamed NoExtField str -> txt $ "-- $" <> T.pack str
  where
    -- Add a comma to a import-export list element
    withComma m =
      case encLayout of
        SingleLine ->
          case relativePos of
            SinglePos -> void m
            FirstPos -> m >> comma
            MiddlePos -> m >> comma
            LastPos -> void m
        MultiLine -> do
          case commaStyle of
            Leading ->
              case relativePos of
                FirstPos -> m
                SinglePos -> m
                _ -> comma >> space >> m
            Trailing -> m >> comma

----------------------------------------------------------------------------

-- | Unlike the version in `Ormolu.Utils`, this version handles explicitly leading export documentation
attachRelativePos' :: [LIE GhcPs] -> [(RelativePos, LIE GhcPs)]
attachRelativePos' = \case
  [] -> []
  [x] -> [(SinglePos, x)]
  -- Check if leading export is a Doc
  (x@(L _ IEDoc {}) : xs) -> (FirstPos, x) : markDoc xs
  (x@(L _ IEGroup {}) : xs) -> (FirstPos, x) : markDoc xs
  (x@(L _ IEDocNamed {}) : xs) -> (FirstPos, x) : markDoc xs
  (x : xs) -> (FirstPos, x) : markLast xs
  where
    -- Mark leading documentation, making sure the first export gets assigned
    -- a `FirstPos`
    markDoc [] = []
    markDoc [x] = [(LastPos, x)]
    markDoc (x@(L _ IEDoc {}) : xs) = (MiddlePos, x) : markDoc xs
    markDoc (x@(L _ IEGroup {}) : xs) = (MiddlePos, x) : markDoc xs
    markDoc (x@(L _ IEDocNamed {}) : xs) = (MiddlePos, x) : markDoc xs
    -- First export after a Doc gets assigned a `FirstPos`
    markDoc (x : xs) = (FirstPos, x) : markLast xs

    markLast [] = []
    markLast [x] = [(LastPos, x)]
    markLast (x : xs) = (MiddlePos, x) : markLast xs

-- Unlike the versions in 'Ormolu.Printer.Combinators', these do not depend on
-- whether 'leadingCommas' is set. This is useful here is we choose to keep
-- import and export lists independent of that setting.

-- | Delimiting combination with 'comma'. To be used with 'sep'.
commaDel' :: R ()
commaDel' = comma >> breakpoint

-- | Surround given entity by parentheses @(@ and @)@.
parens' :: Bool -> R () -> R ()
parens' topLevelImport m =
  getPrinterOpt poDiffFriendlyImportExport >>= \case
    True -> do
      txt "("
      breakpoint'
      sitcc body
      vlayout (txt ")") (inciBy (-1) trailingParen)
    False -> do
      txt "("
      body
      txt ")"
  where
    body = vlayout singleLine multiLine
    singleLine = m
    multiLine = do
      commaStyle <- getPrinterOpt poIECommaStyle
      case commaStyle of
        -- On leading commas, list elements are inline with the enclosing parentheses
        Leading -> do
          space
          m
          newline
        -- On trailing commas, list elements are indented
        Trailing -> do
          space
          sitcc m
          newline
    trailingParen = if topLevelImport then txt " )" else txt ")"

breakIfNotDiffFriendly :: R ()
breakIfNotDiffFriendly =
  getPrinterOpt poDiffFriendlyImportExport >>= \case
    True -> space
    False -> breakpoint
