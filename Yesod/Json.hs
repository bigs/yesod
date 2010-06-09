-- | Efficient generation of JSON documents, with HTML-entity encoding handled via types.
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE CPP #-}
module Yesod.Json
    ( -- * Monad
      Json
    , jsonToContent
    , jsonToRepJson
      -- * Generate Json output
    , jsonScalar
    , jsonList
    , jsonMap
#if TEST
    , testSuite
#endif
    )
    where

import qualified Data.ByteString.Char8 as S
import qualified Data.ByteString.Lazy.Char8 as L
import Data.Char (isControl)
import Yesod.Hamlet
import Yesod.Handler
import Numeric (showHex)
import Data.Monoid (Monoid (..))

#if TEST
import Test.Framework (testGroup, Test)
import Test.Framework.Providers.HUnit
import Test.HUnit hiding (Test)
import Data.ByteString.Lazy.Char8 (unpack)
import Yesod.Content hiding (testSuite)
#else
import Yesod.Content
#endif

-- | A monad for generating Json output. In truth, it is just a newtype wrapper
-- around 'Hamlet'; we thereby get the benefits of Hamlet (interleaving IO and
-- enumerator output) without accidently mixing non-JSON content.
--
-- This is an opaque type to avoid any possible insertion of non-JSON content.
-- Due to the limited nature of the JSON format, you can create any valid JSON
-- document you wish using only 'jsonScalar', 'jsonList' and 'jsonMap'.
newtype Json = Json { unJson :: Html }
    deriving Monoid

-- | Extract the final result from the given 'Json' value.
--
-- See also: applyLayoutJson in "Yesod.Yesod".
jsonToContent :: Json -> GHandler sub master Content
jsonToContent = return . toContent . renderHtml . unJson

-- | Wraps the 'Content' generated by 'jsonToContent' in a 'RepJson'.
jsonToRepJson :: Json -> GHandler sub master RepJson
jsonToRepJson = fmap RepJson . jsonToContent

-- | Outputs a single scalar. This function essentially:
--
-- * Performs HTML entity escaping as necesary.
--
-- * Performs JSON encoding.
--
-- * Wraps the resulting string in quotes.
jsonScalar :: Html -> Json
jsonScalar s = Json $ mconcat
    [ preEscapedString "\""
    , unsafeBytestring $ S.concat $ L.toChunks $ encodeJson $ renderHtml s
    , preEscapedString "\""
    ]
  where
    encodeJson = L.concatMap (L.pack . encodeJsonChar)

    encodeJsonChar '\b' = "\\b"
    encodeJsonChar '\f' = "\\f"
    encodeJsonChar '\n' = "\\n"
    encodeJsonChar '\r' = "\\r"
    encodeJsonChar '\t' = "\\t"
    encodeJsonChar '"' = "\\\""
    encodeJsonChar '\\' = "\\\\"
    encodeJsonChar c
        | not $ isControl c = [c]
        | c < '\x10'   = '\\' : 'u' : '0' : '0' : '0' : hexxs
        | c < '\x100'  = '\\' : 'u' : '0' : '0' : hexxs
        | c < '\x1000' = '\\' : 'u' : '0' : hexxs
        where hexxs = showHex (fromEnum c) ""
    encodeJsonChar c = [c]

-- | Outputs a JSON list, eg [\"foo\",\"bar\",\"baz\"].
jsonList :: [Json] -> Json
jsonList [] = Json $ preEscapedString "[]"
jsonList (x:xs) = mconcat
    [ Json $ preEscapedString "["
    , x
    , mconcat $ map go xs
    , Json $ preEscapedString "]"
    ]
  where
    go = mappend (Json $ preEscapedString ",")

-- | Outputs a JSON map, eg {\"foo\":\"bar\",\"baz\":\"bin\"}.
jsonMap :: [(String, Json)] -> Json
jsonMap [] = Json $ preEscapedString "{}"
jsonMap (x:xs) = mconcat
    [ Json $ preEscapedString "{"
    , go x
    , mconcat $ map go' xs
    , Json $ preEscapedString "}"
    ]
  where
    go' y = mappend (Json $ preEscapedString ",") $ go y
    go (k, v) = mconcat
        [ jsonScalar $ string k
        , Json $ preEscapedString ":"
        , v
        ]

#if TEST

testSuite :: Test
testSuite = testGroup "Yesod.Json"
    [ testCase "simple output" caseSimpleOutput
    ]

caseSimpleOutput :: Assertion
caseSimpleOutput = do
    let j = do
        jsonMap
            [ ("foo" , jsonList
                [ jsonScalar $ preEscapedString "bar"
                , jsonScalar $ preEscapedString "baz"
                ])
            ]
    "{\"foo\":[\"bar\",\"baz\"]}" @=? unpack (renderHtml $ unJson j)

#endif
