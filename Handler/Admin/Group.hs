{-# LANGUAGE TupleSections, OverloadedStrings, ExistentialQuantification #-}
module Handler.Admin.Group where

import           Import
import           Yesod.Auth
import qualified Data.Text            as T
import           Handler.Admin.Modlog (addModlogEntry)
-------------------------------------------------------------------------------------------------------------
groupsForm :: Html ->
             MForm Handler (FormResult ( Text -- ^ Group name
                                       , Bool -- ^ Permission to manage threads
                                       , Bool -- ^ ... boards
                                       , Bool -- ^ ... users
                                       , Bool -- ^ ... config
                                       , Bool -- ^ Permission to delete posts
                                       , Bool -- ^ Permission to view admin panel
                                       , Bool -- ^ Permission to manage bans
                                       , Bool -- ^ Permission to edit any post
                                       , Bool -- ^ Permission to edit any post without saving history  
                                       , Bool -- ^ Permission to use additional markup
                                       , Bool -- ^ Permission to view poster's IP and ID
                                       , Bool -- ^ Permission to view moderation log
                                       , Bool -- ^ Permission to use hellbanning
                                       , Bool -- ^ Permission to change censorship rating
                                       ), Widget)
groupsForm extra = do
  (nameRes         , nameView        ) <- mreq textField     "" Nothing
  (manageThreadRes , manageThreadView) <- mreq checkBoxField "" Nothing
  (manageBoardRes  , manageBoardView ) <- mreq checkBoxField "" Nothing
  (manageUsersRes  , manageUsersView ) <- mreq checkBoxField "" Nothing
  (manageConfigRes , manageConfigView) <- mreq checkBoxField "" Nothing
  (deletePostsRes  , deletePostsView ) <- mreq checkBoxField "" Nothing
  (managePanelRes  , managePanelView ) <- mreq checkBoxField "" Nothing
  (manageBanRes    , manageBanView   ) <- mreq checkBoxField "" Nothing
  (editPostsRes    , editPostsView   ) <- mreq checkBoxField "" Nothing
  (shadowEditRes   , shadowEditView  ) <- mreq checkBoxField "" Nothing
  (aMarkupRes      , aMarkupView     ) <- mreq checkBoxField "" Nothing
  (viewIPAndIDRes  , viewIPAndIDView ) <- mreq checkBoxField "" Nothing
  (viewModlogRes   , viewModlogView  ) <- mreq checkBoxField "" Nothing
  (hellbanningRes  , hellbanningView ) <- mreq checkBoxField "" Nothing
  (ratingRes       , ratingView      ) <- mreq checkBoxField "" Nothing

  let result = (,,,,,,,,,,,,,,)<$> nameRes        <*>
               manageThreadRes <*> manageBoardRes <*> manageUsersRes <*>
               manageConfigRes <*> deletePostsRes <*> managePanelRes <*>
               manageBanRes    <*> editPostsRes   <*> shadowEditRes  <*>
               aMarkupRes      <*> viewIPAndIDRes <*> viewModlogRes  <*>
               hellbanningRes  <*> ratingRes
      widget = $(widgetFile "admin/groups-form")
  return (result, widget)

showPermission :: Permission -> AppMessage
showPermission p = fromJust $ lookup p xs
  where xs = [(ManageThreadP    , MsgManageThread    )
             ,(ManageBoardP     , MsgManageBoard     )
             ,(ManageUsersP     , MsgManageUsers     )
             ,(ManageConfigP    , MsgManageConfig    )
             ,(DeletePostsP     , MsgDeletePosts     )
             ,(ManagePanelP     , MsgManagePanel     )
             ,(ManageBanP       , MsgManageBan       )
             ,(EditPostsP       , MsgEditPosts       )
             ,(ShadowEditP      , MsgShadowEdit      )
             ,(AdditionalMarkupP, MsgAdditionalMarkup)
             ,(ViewIPAndIDP     , MsgViewIPAndID     )
             ,(ViewModlogP      , MsgViewModlog      )
             ,(HellBanP         , MsgHellbanning     )
             ,(ChangeFileRatingP, MsgChangeFileRating)
             ]

getManageGroupsR :: Handler Html
getManageGroupsR = do
  muser       <- maybeAuth
  permissions <- getPermissions <$> getMaybeGroup muser
  
  groups <- map entityVal <$> runDB (selectList ([]::[Filter Group]) [])
  (formWidget, formEnctype) <- generateFormPost groupsForm

  nameOfTheBoard  <- extraSiteName <$> getExtra
  msgrender       <- getMessageRender
  defaultLayout $ do
    setTitle $ toHtml $ nameOfTheBoard <> titleDelimiter <> msgrender MsgGroups
    $(widgetFile "admin/groups")
  
postManageGroupsR :: Handler Html
postManageGroupsR = do
  ((result, _), _) <- runFormPost groupsForm 
  let msgRedirect msg = setMessageI msg >> redirect ManageGroupsR
  case result of
    FormFailure [] -> msgRedirect MsgBadFormData
    FormFailure xs -> msgRedirect (MsgError $ T.intercalate "; " xs) 
    FormMissing    -> msgRedirect MsgNoFormData
    FormSuccess (name         , manageThread , manageBoard      , manageUsers,
                 manageConfig , deletePostsP , managePanel      , manageBan  ,
                 editPosts    , shadowEdit   , aMarkup          , viewIPAndID,
                 viewModLog   , hellbanning  , changeFileRating
                ) -> do
      let permissions = [(ManageThreadP    ,manageThread), (ManageBoardP,manageBoard ), (ManageUsersP ,manageUsers)
                        ,(ManageConfigP    ,manageConfig), (DeletePostsP,deletePostsP), (ManagePanelP ,managePanel)
                        ,(ManageBanP       ,manageBan   ), (EditPostsP  ,editPosts   ), (ShadowEditP  ,shadowEdit )
                        ,(AdditionalMarkupP,aMarkup     ), (ViewIPAndIDP,viewIPAndID ), (ViewModlogP  ,viewModLog )
                        ,(HellBanP         ,hellbanning ), (ChangeFileRatingP,changeFileRating)
                        ]
          newGroup = Group { groupName        = name
                           , groupPermissions = map fst $ filter snd permissions
                           }
      g <- runDB $ getBy $ GroupUniqName name
      if isJust g
        then addModlogEntry (MsgModlogUpdateGroup name) >> void (runDB $ replace (entityKey $ fromJust g) newGroup)
        else addModlogEntry (MsgModlogAddGroup    name) >> void (runDB $ insert newGroup)
      msgRedirect MsgGroupAddedOrUpdated

getDeleteGroupsR :: Text -> Handler ()
getDeleteGroupsR group = do
  delGroup  <- runDB $ selectFirst [GroupName ==. group] []
  when (isNothing delGroup) $ setMessageI MsgGroupDoesNotExist >> redirect ManageGroupsR
  usrGroup <- getMaybeGroup =<< maybeAuth
  when (isNothing usrGroup) notFound

  groups <- map (groupPermissions . entityVal) <$> runDB (selectList ([]::[Filter Group]) [])
  when ((ManageUsersP `notElem` groupPermissions (entityVal $ fromJust delGroup) ) ||
        ((>1) $ length $ filter (ManageUsersP `elem`) groups)) $ do
    void $ runDB $ deleteWhere [GroupName ==. group]
    addModlogEntry $ MsgModlogDelGroup group
    setMessageI MsgGroupDeleted >> redirect ManageGroupsR
  setMessageI MsgYouAreTheOnlyWhoCanManageUsers >> redirect ManageGroupsR
