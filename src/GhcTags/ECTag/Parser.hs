-- | Parser combinators for exuberant ctags
--
module GhcTags.ECTag.Parser
  ( parseTagsFile
  -- * parse a ctag
  , parseTag
  -- * parse a pseudo-ctag
  , parseHeader
  ) where

import           Control.Applicative (many, (<|>))
import           Control.DeepSeq (NFData)
import           Data.Attoparsec.Text  (Parser, (<?>))
import qualified Data.Attoparsec.Text  as AT
import           Data.Functor (($>))
import           qualified Data.Map.Strict as Map
import           Data.Text          (Text)
import qualified Data.Text          as Text

import           GhcTags.Tag
import           GhcTags.ECTag.Header
import           GhcTags.ECTag.Utils



-- | Parser for a 'ECTag' from a single text line.
--
parseTag :: Parser (TagFileName, ECTag)
parseTag =
      (\tagName tagFileName tagAddr (tagKind, tagFields)
        -> (tagFileName, Tag { tagName
                             , tagAddr
                             , tagKind
                             , tagFields
                             , tagDefinition = NoTagDefinition
                             })
      )
    <$> parseTagName
    <*  separator

    <*> parseFileName
    <*  separator

    <*> parseTagAddress

    <*> (  -- kind followed by list of fields or end of line
              (,) <$  AT.string ";\""
                  <*  separator
                  <*> (charToTagKind <$> AT.satisfy notTabOrNewLine)
                  <*> fieldsInLine

          -- list of fields (kind field might be later, but don't check it, we
          -- always format it as the first field) or end of line.
          <|> (NoKind, ) <$ AT.string ";\""
                         <*> fieldsInLine

          <|> endOfLine $> (NoKind, mempty)
        )

  where
    fieldsInLine :: Parser ECTagFields
    fieldsInLine = separator *> parseFields <* endOfLine
                   <|>
                   endOfLine $> mempty

    separator :: Parser Char
    separator = AT.char '\t'

    parseTagName :: Parser TagName
    parseTagName = TagName <$> AT.takeWhile (/= '\t')
                           <?> "parsing tag name failed"

    parseFileName :: Parser TagFileName
    parseFileName = TagFileName <$> AT.takeWhile (/= '\t')

    parseExSearchCommand :: Parser ExCommand
    parseExSearchCommand = ExCommand <$> AT.scan (Nothing, '\0', '\\') go
      where
        go :: (Maybe Char, Char, Char) -> Char -> Maybe (Maybe Char, Char, Char)
        go (Nothing, c0, c1) delim
          -- Support both forward and backward searches.
          | delim == '/' || delim == '?' = go (Just delim, c0, c1) delim
          | otherwise                    = Nothing

        go (jdelim@(Just delim), c0, c1) c2
          -- Continue until the next unescaped delimiter.
          | c0 /= '\\' && c1 == delim = Nothing
          | otherwise                 = Just (jdelim, c1, c2)

    -- We only parse `TagLine` or `TagCommand`.
    parseTagAddress :: Parser ECTagAddress
    parseTagAddress = TagLine <$> AT.decimal
                      <|>
                      TagCommand <$> parseExSearchCommand

    parseFields :: Parser ECTagFields
    parseFields = TagFields <$> AT.sepBy parseField separator


parseField :: Parser TagField
parseField =
         TagField
     <$> AT.takeWhile (\x -> x /= ':' && notTabOrNewLine x)
     <*  AT.char ':'
     <*> AT.takeWhile notTabOrNewLine


-- | A tag file parser.
--
parseTags :: Parser ([Header], ECTagMap)
parseTags = (\headers tags -> (headers, Map.fromListWith (++) $ map sndList tags))
  <$> many parseHeader
  <*> many parseTag
  where
    sndList (file, tag) = (file, [tag])

parseHeader :: Parser Header
parseHeader = do
    e <- AT.string "!_TAG_" $> False
         <|>
         AT.string "!_" $> True
    case e of
      True ->
               flip parsePseudoTagArgs (AT.takeWhile notTabOrNewLine)
             . PseudoTag
         =<< AT.takeWhile (\x -> notTabOrNewLine x && x /= '!')
      False -> do
        headerType <-
              AT.string "FILE_ENCODING"     $> SomeHeaderType FileEncoding
          <|> AT.string "FILE_FORMAT"       $> SomeHeaderType FileFormat
          <|> AT.string "FILE_SORTED"       $> SomeHeaderType FileSorted
          <|> AT.string "OUTPUT_MODE"       $> SomeHeaderType OutputMode
          <|> AT.string "KIND_DESCRIPTION"  $> SomeHeaderType KindDescription
          <|> AT.string "KIND_SEPARATOR"    $> SomeHeaderType KindSeparator
          <|> AT.string "PROGRAM_AUTHOR"    $> SomeHeaderType ProgramAuthor
          <|> AT.string "PROGRAM_NAME"      $> SomeHeaderType ProgramName
          <|> AT.string "PROGRAM_URL"       $> SomeHeaderType ProgramUrl
          <|> AT.string "PROGRAM_VERSION"   $> SomeHeaderType ProgramVersion
          <|> AT.string "EXTRA_DESCRIPTION" $> SomeHeaderType ExtraDescription
          <|> AT.string "FIELD_DESCRIPTION" $> SomeHeaderType FieldDescription
        case headerType of
          SomeHeaderType ht@FileEncoding ->
              parsePseudoTagArgs ht (AT.takeWhile notTabOrNewLine)
          SomeHeaderType ht@FileFormat ->
              parsePseudoTagArgs ht AT.decimal
          SomeHeaderType ht@FileSorted ->
              parsePseudoTagArgs ht AT.decimal
          SomeHeaderType ht@OutputMode ->
              parsePseudoTagArgs ht (AT.takeWhile notTabOrNewLine)
          SomeHeaderType ht@KindDescription ->
              parsePseudoTagArgs ht (AT.takeWhile notTabOrNewLine)
          SomeHeaderType ht@KindSeparator ->
              parsePseudoTagArgs ht (AT.takeWhile notTabOrNewLine)
          SomeHeaderType ht@ProgramAuthor ->
              parsePseudoTagArgs ht (AT.takeWhile notTabOrNewLine)
          SomeHeaderType ht@ProgramName ->
              parsePseudoTagArgs ht (AT.takeWhile notTabOrNewLine)
          SomeHeaderType ht@ProgramUrl ->
              parsePseudoTagArgs ht (AT.takeWhile notTabOrNewLine)
          SomeHeaderType ht@ProgramVersion ->
              parsePseudoTagArgs ht (AT.takeWhile notTabOrNewLine)
          SomeHeaderType ht@ExtraDescription ->
              parsePseudoTagArgs ht (AT.takeWhile notTabOrNewLine)
          SomeHeaderType ht@FieldDescription ->
              parsePseudoTagArgs ht (AT.takeWhile notTabOrNewLine)
          SomeHeaderType PseudoTag {} ->
              error "parseHeader: impossible happened"

  where
    parsePseudoTagArgs :: (NFData ty, Show ty)
                       => HeaderType ty
                       -> Parser ty
                       -> Parser Header
    parsePseudoTagArgs ht parseArg =
              Header ht
          <$> ( (Just <$> (AT.char '!' *> AT.takeWhile notTabOrNewLine))
                <|> pure Nothing
              )
          <*> (AT.char '\t' *> parseArg)
          <*> (AT.char '\t' *> parseComment)

    parseComment :: Parser Text
    parseComment =
         AT.char '/'
      *> (Text.init <$> AT.takeWhile notNewLine)
      <* endOfLine



-- | Parse a "tag" file.
--
parseTagsFile :: Text
              -> IO (Either String ([Header], ECTagMap))
parseTagsFile =
      fmap AT.eitherResult
    . AT.parseWith (pure mempty) parseTags


--
-- Utils
--


-- | Unlike 'AT.endOfLine', it also matches for a single '\r' characters (which
-- marks enf of lines on darwin).
--
endOfLine :: Parser ()
endOfLine = AT.string "\r\n" $> ()
        <|> AT.char '\r' $> ()
        <|> AT.char '\n' $> ()


notTabOrNewLine :: Char -> Bool
notTabOrNewLine = \x -> x /= '\t' && notNewLine x

notNewLine :: Char -> Bool
notNewLine = \x -> x /= '\n' && x /= '\r'
