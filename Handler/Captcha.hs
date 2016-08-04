module Handler.Captcha where
 
import Import
import System.Random (randomIO)
import System.Directory (removeFile, doesFileExist)
import System.Process
import qualified Data.Text as T

captchaExt :: String
captchaExt = ".png"

makeCaptcha :: String -> Handler (Text, Text)
makeCaptcha path = do
  captcha <- appCaptcha . appSettings <$> getYesod
  liftIO $ (first T.strip . (pack***pack) . read) <$> readProcess (unpack captcha) [path] ""

captchaWidget :: Widget
captchaWidget = do
  (path, hint) <- handlerToWidget $ do
    AppSettings{..} <- appSettings <$> getYesod
    oldCId <- lookupSession "captchaId"
    let path = captchaFilePath appStaticDir (unpack $ fromJust oldCId) ++ captchaExt
      in when (isJust oldCId) $ whenM (liftIO $ doesFileExist path) $ liftIO $ removeFile path
    cId <- liftIO (abs <$> randomIO :: IO Int)
    setSession "captchaId" (tshow cId)
    (value, hint) <- makeCaptcha $ captchaFilePath appStaticDir (show cId) ++ captchaExt
    setSession "captchaValue" value
    setSession "captchaHint"  hint
    return (captchaFilePath appStaticDir (show cId) ++ captchaExt, hint)
  [whamlet|
    <img #captcha onclick="refreshCaptcha()" src=#{path}>
    #{preEscapedToHtml hint}
  |]

getCaptchaR :: Handler Html
getCaptchaR = bareLayout $ toWidget captchaWidget

getCheckCaptchaR :: Text -> Handler TypedContent
getCheckCaptchaR captcha = do
  mCaptchaValue <- lookupSession "captchaValue"
  case mCaptchaValue of
    Just c  -> selectRep $ provideJson $ object [("result", if (T.toLower captcha) == (T.toLower c) then "true" else "false" )]
    Nothing -> selectRep $ provideJson $ object [("result", "false" )]

checkCaptcha :: Maybe Text -> Handler () -> Handler ()
checkCaptcha mCaptcha wrongCaptchaRedirect = do
  mCaptchaValue <- lookupSession "captchaValue"
  mCaptchaId    <- lookupSession "captchaId"
  deleteSession "captchaValue"
  deleteSession "captchaId"
  AppSettings{..} <- appSettings <$> getYesod
  case mCaptchaId of
   Just cId -> do
     let path = captchaFilePath appStaticDir (unpack cId) ++ captchaExt
     whenM (liftIO $ doesFileExist path) $
       liftIO $ removeFile path
     when ((T.toLower <$>  mCaptchaValue) /= (T.toLower <$> mCaptcha)) wrongCaptchaRedirect
   _        -> wrongCaptchaRedirect
