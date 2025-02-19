-- | 'bytestring''s 'Builder' for a 'Tag'
--
module GhcTags.ECTag.Formatter
  ( formatTagsFile
  -- * format a ctag
  , formatTag
  -- * format a pseudo-ctag
  , formatHeader
  ) where

import           Data.ByteString.Builder (Builder)
import qualified Data.ByteString.Builder as BS
import           Data.Char (isAscii)
import           Data.List (sortBy)
import qualified Data.Map.Strict as Map
import           Data.Text          (Text)
import qualified Data.Text.Encoding as Text

import           GhcTags.Tag
import           GhcTags.Utils (endOfLine)
import           GhcTags.ECTag.Header
import           GhcTags.ECTag.Utils


-- | 'ByteString' 'Builder' for a single line.
--
formatTag :: TagFileName -> ECTag -> Builder
formatTag fileName Tag { tagName, tagAddr, tagKind, tagFields = TagFields tagFields } =

       (BS.byteString . Text.encodeUtf8 . getTagName $ tagName)
    <> BS.charUtf8 '\t'

    <> (BS.byteString . Text.encodeUtf8 . getTagFileName $ fileName)
    <> BS.charUtf8 '\t'

    <> formatTagAddress tagAddr
    -- we are using extended format: '_TAG_FILE_FROMAT	2'
    <> BS.stringUtf8 ";\""

    -- tag kind: we are encoding them using field syntax: this is because Vim
    -- is using them in the right way: https://github.com/vim/vim/issues/5724
    <> formatKindChar tagKind

    -- tag fields
    <> foldMap ((BS.charUtf8 '\t' <>) . formatField) tagFields

    <> BS.stringUtf8 endOfLine

  where

    formatTagAddress :: ECTagAddress -> Builder
    formatTagAddress (TagLine lineNo) =
      BS.intDec lineNo
    formatTagAddress (TagCommand exCommand) =
      BS.byteString . Text.encodeUtf8 . getExCommand $ exCommand     

    formatKindChar :: ECTagKind -> Builder
    formatKindChar tk =
      case tagKindToChar tk of
        Nothing -> mempty
        Just c | isAscii c -> BS.charUtf8 '\t' <> BS.charUtf8 c
               | otherwise -> BS.stringUtf8 "\tkind:" <> BS.charUtf8 c


formatField :: TagField -> Builder
formatField TagField { fieldName, fieldValue } =
      BS.byteString (Text.encodeUtf8 fieldName)
   <> BS.charUtf8 ':'
   <> BS.byteString (Text.encodeUtf8 fieldValue)


formatHeader :: Header -> Builder
formatHeader Header { headerType, headerLanguage, headerArg, headerComment } =
    case headerType of
      FileEncoding ->
        formatTextHeaderArgs "FILE_ENCODING"     headerLanguage headerArg headerComment
      FileFormat ->
        formatIntHeaderArgs "FILE_FORMAT"        headerLanguage headerArg headerComment
      FileSorted ->
        formatIntHeaderArgs "FILE_SORTED"        headerLanguage headerArg headerComment
      OutputMode ->
        formatTextHeaderArgs "OUTPUT_MODE"       headerLanguage headerArg headerComment
      KindDescription ->
        formatTextHeaderArgs "KIND_DESCRIPTION"  headerLanguage headerArg headerComment
      KindSeparator ->
        formatTextHeaderArgs "KIND_SEPARATOR"    headerLanguage headerArg headerComment
      ProgramAuthor ->
        formatTextHeaderArgs "PROGRAM_AUTHOR"    headerLanguage headerArg headerComment
      ProgramName ->
        formatTextHeaderArgs "PROGRAM_NAME"      headerLanguage headerArg headerComment
      ProgramUrl ->
        formatTextHeaderArgs "PROGRAM_URL"       headerLanguage headerArg headerComment
      ProgramVersion ->
        formatTextHeaderArgs "PROGRAM_VERSION"   headerLanguage headerArg headerComment
      ExtraDescription ->
        formatTextHeaderArgs "EXTRA_DESCRIPTION" headerLanguage headerArg headerComment
      FieldDescription ->
        formatTextHeaderArgs "FIELD_DESCRIPTION" headerLanguage headerArg headerComment
      PseudoTag name ->
        formatHeaderArgs (BS.byteString . Text.encodeUtf8)
                         "!_" name headerLanguage headerArg headerComment
  where
    formatHeaderArgs :: (ty -> Builder)
                     -> String
                     -> Text
                     -> Maybe Text
                     -> ty
                     -> Text
                     -> Builder
    formatHeaderArgs formatArg prefix headerName language arg comment =
         BS.stringUtf8 prefix
      <> BS.byteString (Text.encodeUtf8 headerName)
      <> foldMap ((BS.charUtf8 '!' <>) . BS.byteString . Text.encodeUtf8) language
      <> BS.charUtf8 '\t'
      <> formatArg arg
      <> BS.stringUtf8 "\t/"
      <> BS.byteString (Text.encodeUtf8 comment)
      <> BS.charUtf8 '/'
      <> BS.stringUtf8 endOfLine

    formatTextHeaderArgs = formatHeaderArgs (BS.byteString . Text.encodeUtf8) "!_TAG_"
    formatIntHeaderArgs  = formatHeaderArgs BS.intDec "!_TAG_"


-- | 'ByteString' 'Builder' for Exuberant Ctags 'Tag' file.
--
formatTagsFile :: [Header]          -- ^ Headers
               -> ECTagMap           -- ^ 'ECTag's
               -> Builder
formatTagsFile headers tags = foldMap formatHeader headers
  <> (foldMap formatTagLine . sortBy compareTagLine
                            . Map.foldrWithKey concatTags []
                            $ tags)
  where
    concatTags :: TagFileName -> [ECTag] -> [ECTagLine] -> [ECTagLine]
    concatTags file ts acc = map (ECTagLine file) ts ++ acc

    compareTagLine :: ECTagLine -> ECTagLine -> Ordering
    compareTagLine (ECTagLine file0 tag0) (ECTagLine file1 tag1) =
      compareTags tag0 tag1 <> compare file0 file1

    formatTagLine :: ECTagLine -> Builder
    formatTagLine (ECTagLine file tag) = formatTag file tag

-- | Helper data type for 'formatTagsFile'.
data ECTagLine = ECTagLine TagFileName ECTag
