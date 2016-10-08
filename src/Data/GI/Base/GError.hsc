{-# LANGUAGE DeriveDataTypeable, ScopedTypeVariables #-}

-- | To catch GError exceptions use the
-- catchGError* or handleGError* functions. They work in a similar
-- way to the standard 'Control.Exception.catch' and
-- 'Control.Exception.handle' functions.
--
-- To catch just a single specific error use 'catchGErrorJust' \/
-- 'handleGErrorJust'. To catch any error in a particular error domain
-- use 'catchGErrorJustDomain' \/ 'handleGErrorJustDomain'
--
-- For convenience, generated code also includes specialized variants
-- of 'catchGErrorJust' \/ 'handleGErrorJust' for each error type. For
-- example, for errors of type 'GI.GdkPixbuf.PixbufError' one could
-- invoke 'GI.GdkPixbuf.catchPixbufError' \/
-- 'GI.GdkPixbuf.handlePixbufError'. The definition is simply
--
-- > catchPixbufError :: IO a -> (PixbufError -> GErrorMessage -> IO a) -> IO a
-- > catchPixbufError = catchGErrorJustDomain
--
-- Notice that the type is suitably specialized, so only
-- errors of type 'GI.GdkPixbuf.PixbufError' will be caught.
module Data.GI.Base.GError
    (
    -- * Unpacking GError
    --
      GError(..)
    , gerrorDomain
    , gerrorCode
    , gerrorMessage

    , GErrorDomain
    , GErrorCode
    , GErrorMessage

    -- * Catching GError exceptions
    , catchGErrorJust
    , catchGErrorJustDomain

    , handleGErrorJust
    , handleGErrorJustDomain

    -- * Creating new 'GError's
    , gerrorNew

    -- * Implementation specific details
    -- | The following are used in the implementation
    -- of the bindings, and are in general not necessary for using the
    -- API.
    , GErrorClass(..)

    , propagateGError
    , checkGError

    ) where

#if __GLASGOW_HASKELL__ < 710
import Control.Applicative ((<$>))
#endif

import Foreign (poke, peek)
import Foreign.Ptr (Ptr, plusPtr, nullPtr)
import Foreign.C
import Control.Exception
import Data.Text (Text)
import qualified Data.Text as T
import Data.Typeable (Typeable)
import Data.Int
import Data.Word

import System.IO.Unsafe (unsafePerformIO)

import Data.GI.Base.BasicTypes (BoxedObject(..), GType(..), ManagedPtr)
import Data.GI.Base.BasicConversions (withTextCString, cstringToText)
import Data.GI.Base.ManagedPtr (wrapBoxed, withManagedPtr)
import Data.GI.Base.Utils (allocMem, freeMem)

#include <glib.h>

-- | A GError, consisting of a domain, code and a human readable
-- message. These can be accessed by 'gerrorDomain', 'gerrorCode' and
-- 'gerrorMessage' below.
newtype GError = GError (ManagedPtr GError)
    deriving (Typeable)

instance Show GError where
    show gerror = unsafePerformIO $ do
                       code <- gerrorCode gerror
                       message <- gerrorMessage gerror
                       return $ T.unpack message ++ " (" ++ show code ++ ")"

instance Exception GError

foreign import ccall "g_error_get_type" g_error_get_type :: IO GType

instance BoxedObject GError where
    boxedType _ = g_error_get_type

-- | A GQuark.
type GQuark = #type GQuark

-- | A code used to identify the "namespace" of the error. Within each error
--   domain all the error codes are defined in an enumeration. Each gtk\/gnome
--   module that uses GErrors has its own error domain. The rationale behind
--   using error domains is so that each module can organise its own error codes
--   without having to coordinate on a global error code list.
type GErrorDomain  = GQuark

-- | A code to identify a specific error within a given 'GErrorDomain'. Most of
--   time you will not need to deal with this raw code since there is an
--   enumeration type for each error domain. Of course which enumeration to use
--   depends on the error domain, but if you use 'catchGErrorJustDomain' or
--   'handleGErrorJustDomain', this is worked out for you automatically.
type GErrorCode = #type gint

-- | A human readable error message.
type GErrorMessage = Text

foreign import ccall "g_error_new_literal" g_error_new_literal ::
    GQuark -> GErrorCode -> CString -> IO (Ptr GError)

-- | Create a new 'GError'.
gerrorNew :: GErrorDomain -> GErrorCode -> GErrorMessage -> IO GError
gerrorNew domain code message =
    withTextCString message $ \cstring ->
        g_error_new_literal domain code cstring >>= wrapBoxed GError

-- | Return the domain for the given `GError`. This is a GQuark, a
-- textual representation can be obtained with
-- `GI.GLib.quarkToString`.
gerrorDomain :: GError -> IO GQuark
gerrorDomain gerror =
    withManagedPtr gerror $ \ptr ->
      peek $ ptr `plusPtr` #{offset GError, domain}

-- | The numeric code for the given `GError`.
gerrorCode :: GError -> IO GErrorCode
gerrorCode gerror =
    withManagedPtr gerror $ \ptr ->
        peek $ ptr `plusPtr` #{offset GError, code}

-- | A text message describing the `GError`.
gerrorMessage :: GError -> IO GErrorMessage
gerrorMessage gerror =
    withManagedPtr gerror $ \ptr ->
      (peek $ ptr `plusPtr` #{offset GError, message}) >>= cstringToText

-- | Each error domain's error enumeration type should be an instance of this
--   class. This class helps to hide the raw error and domain codes from the
--   user.
--
-- Example for 'GI.GdkPixbuf.PixbufError':
--
-- > instance GErrorClass PixbufError where
-- >   gerrorClassDomain _ = "gdk-pixbuf-error-quark"
--
class Enum err => GErrorClass err where
  gerrorClassDomain :: err -> Text   -- ^ This must not use the value of its
                                     -- parameter so that it is safe to pass
                                     -- 'undefined'.

foreign import ccall unsafe "g_quark_try_string" g_quark_try_string ::
    CString -> IO GQuark

-- | Given the string representation of an error domain returns the
--   corresponding error quark.
gErrorQuarkFromDomain :: Text -> IO GQuark
gErrorQuarkFromDomain domain = withTextCString domain g_quark_try_string

-- | This will catch just a specific GError exception. If you need to catch a
--   range of related errors, 'catchGErrorJustDomain' is probably more
--   appropriate. Example:
--
-- > do image <- catchGErrorJust PixbufErrorCorruptImage
-- >               loadImage
-- >               (\errorMessage -> do log errorMessage
-- >                                    return mssingImagePlaceholder)
--
catchGErrorJust :: GErrorClass err => err  -- ^ The error to catch
                -> IO a                    -- ^ The computation to run
                -> (GErrorMessage -> IO a) -- ^ Handler to invoke if
                                           -- an exception is raised
                -> IO a
catchGErrorJust code action handler = do
  domainQuark <- gErrorQuarkFromDomain $ gerrorClassDomain code
  catch action (handler' domainQuark)
  where handler' quark gerror = do
          domain <- gerrorDomain gerror
          code' <- gerrorCode gerror
          if domain == quark && code' == (fromIntegral . fromEnum) code
          then gerrorMessage gerror >>= handler
          else throw gerror -- Pass it on

-- | Catch all GErrors from a particular error domain. The handler function
--   should just deal with one error enumeration type. If you need to catch
--   errors from more than one error domain, use this function twice with an
--   appropriate handler functions for each.
--
-- > catchGErrorJustDomain
-- >   loadImage
-- >   (\err message -> case err of
-- >       PixbufErrorCorruptImage -> ...
-- >       PixbufErrorInsufficientMemory -> ...
-- >       PixbufErrorUnknownType -> ...
-- >       _ -> ...)
--
catchGErrorJustDomain :: forall err a. GErrorClass err =>
                         IO a        -- ^ The computation to run
                      -> (err -> GErrorMessage -> IO a) -- ^ Handler to invoke if an exception is raised
                      -> IO a
catchGErrorJustDomain action handler = do
  domainQuark <- gErrorQuarkFromDomain $ gerrorClassDomain (undefined::err)
  catch action (handler' domainQuark)
  where handler' quark gerror = do
          domain <- gerrorDomain gerror
          if domain == quark
          then do
            code <- (toEnum . fromIntegral) <$> gerrorCode gerror
            msg <- gerrorMessage gerror
            handler code msg
          else throw gerror

-- | A verson of 'handleGErrorJust' with the arguments swapped around.
handleGErrorJust :: GErrorClass err => err -> (GErrorMessage -> IO a) -> IO a -> IO a
handleGErrorJust code = flip (catchGErrorJust code)

-- | A verson of 'catchGErrorJustDomain' with the arguments swapped around.
handleGErrorJustDomain :: GErrorClass err => (err -> GErrorMessage -> IO a) -> IO a -> IO a
handleGErrorJustDomain = flip catchGErrorJustDomain

-- | Run the given function catching possible 'GError's in its
-- execution. If a 'GError' is emitted this throws the corresponding
-- exception.
propagateGError :: (Ptr (Ptr GError) -> IO a) -> IO a
propagateGError f = checkGError f throw

-- | Like 'propagateGError', but allows to specify a custom handler
-- instead of just throwing the exception.
checkGError :: (Ptr (Ptr GError) -> IO a) -> (GError -> IO a) -> IO a
checkGError f handler = do
  gerrorPtr <- allocMem
  poke gerrorPtr nullPtr
  result <- f gerrorPtr
  gerror <- peek gerrorPtr
  freeMem gerrorPtr
  if gerror /= nullPtr
  then wrapBoxed GError gerror >>= handler
  else return result
