{
        File: uFavoritesManager.pas
        License: GPLv2
        This unit is a part of Free Manga Downloader
}

unit uFavoritesManager;

{$mode delphi}

interface

uses
  Classes, SysUtils, Dialogs, IniFiles, syncobjs, lazutf8classes, FileUtil, fgl,
  uBaseUnit, uData, uDownloadsManager, uFMDThread, uMisc, blcksock;

type
  TFavoriteManager = class;
  TFavoriteTask = class;

  { TFavoriteThread }

  TFavoriteThread = class(TFMDThread)
  protected
    FWebsite, FURL: String;
    procedure SockOnHeartBeat(Sender: TObject);
    procedure Execute; override;
  public
    workCounter: Cardinal;
    getInfo: TMangaInformation;
    task: TFavoriteTask;
    manager: TFavoriteManager;
    constructor Create;
    destructor Destroy; override;
  end;

  TFavoriteThreadList = TFPGList<TFavoriteThread>;

  { TFavoriteTask }

  TFavoriteTask = class(TFMDThread)
  private
    FBtnCaption: String;
  protected
    procedure SyncUpdateBtnCaption;
    procedure SyncShowResult;
    procedure Execute; override;
  public
    CS_Threads: TCriticalSection;
    manager: TFavoriteManager;
    threads: TFavoriteThreadList;
    workCounter: Cardinal;
    constructor Create;
    destructor Destroy; override;
    procedure UpdateBtnCaption(Cap: String);
  end;


  { TFavoriteManager }

  TFavoriteManager = class
  private
    FSortDirection: Boolean;
    FSortColumn: Cardinal;
    FIsAuto, FIsShowDialog,
    // Return true if Favorites is checking
    FIsRunning: Boolean;

    // Move all the task to the left, starting from pos
    procedure MoveLeft(const pos: Cardinal);
    // Move all the task to the right, starting from pos
    procedure MoveRight(const pos: Cardinal);
  public
    Lock: Cardinal;
    // Number of mangas in Favorites
    Count: Cardinal;
    // Number of mangas in Favorites before we perform checking
    CountBeforeChecking: Cardinal;

    favorites: TIniFile;
    // All Favorites information
    favoriteInfo: array of TFavoriteInfo;
    // mangaInfo for generating download tasks
    //mangaInfo: array of TMangaInfo;
    mangaInfo: array of TMangaInfo;

    // Number of working thread
    // For now we always set it to 1
    numberOfThreads: Cardinal;
    // Working threads
    taskthread: TFavoriteTask;
    // Download Manager (passed from mainunit.pas)
    // After favorites run completed, all download jobs will be add to DLManager
    DLManager: TDownloadManager;

    OnUpdateFavorite:
    procedure of object;
    OnUpdateDownload:
    procedure of object;

    constructor Create;
    destructor Destroy; override;

    procedure Run;
    // Show notification form after checking completed
    procedure ShowResult;
    // Remove completed mangas
    procedure RemoveCompletedMangas;
    // Return true if a manga exist in Favorites
    function IsMangaExist(const title, website: String): Boolean;
    function IsMangaExistURL(const website, URL: String): Boolean;
    // Add new manga to the list
    procedure Add(const title, currentChapter, downloadedChapterList,
      website, saveTo, link: String);
    // Merge manga information with a title that already exist in Favorites
    procedure AddMerge(const title, currentChapter, downloadedChapterList,
      website, saveTo, link: String);
    // Merge a favorites.ini with another favorites.ini
    procedure MergeWith(const APath: String);
    // Remove a manga from Favorites
    procedure Remove(const pos: Cardinal; const isBackup: Boolean = True);
    // Restore information from favorites.ini
    procedure Restore;
    // Backup to favorites.ini
    procedure Backup;
    // Abort favorites check
    procedure StopAllAndWait;

    // sorting
    procedure Sort(const AColumn: Cardinal);
    procedure SortNatural(const AColumn: Integer);

    property SortDirection: Boolean read FSortDirection write FSortDirection;
    property SortColumn: Cardinal read FSortColumn write FSortColumn;
    property isAuto: Boolean read FIsAuto write FIsAuto;
    property isShowDialog: Boolean read FIsShowDialog write FIsShowDialog;
    property isRunning: Boolean read FIsRunning write FIsRunning;
  end;

implementation

uses
  frmMain, frmNewChapter;

{ TFavoriteTask }

procedure TFavoriteTask.SyncUpdateBtnCaption;
begin
  MainForm.btFavoritesCheckNewChapter.Caption := FBtnCaption;
end;

procedure TFavoriteTask.SyncShowResult;
begin
  manager.ShowResult;
end;

procedure TFavoriteTask.Execute;
var
  workCounter: Integer;
begin
  try
    workCounter := 0;
    while workCounter < Length(manager.favoriteInfo) do
    begin
      while threads.Count > manager.DLManager.maxDLThreadsPerTask do
      begin
        if Terminated then Break;
        Sleep(250);
      end;
      if Terminated then Break;
      if threads.Count < manager.DLManager.maxDLThreadsPerTask then
      begin
        CS_Threads.Acquire;
        try
          threads.Add(TFavoriteThread.Create);
          threads.Last.task := Self;
          threads.Last.manager := Self.manager;
          threads.Last.workCounter := workCounter;
          threads.Last.Start;
          UpdateBtnCaption(Format('%s <%s>',
            [stFavoritesChecking, manager.favoriteInfo[workCounter].title]));
        finally
          CS_Threads.Release;
        end;
        Inc(workCounter);
      end;
    end;
    while threads.Count > 0 do
      Sleep(250);
    UpdateBtnCaption(stFavoritesCheck);
    if not Terminated then
      Synchronize(SyncShowResult);
  except
    on E: Exception do
      MainForm.ExceptionHandler(Self, E);
  end;
  manager.isRunning := False;
end;

constructor TFavoriteTask.Create;
begin
  inherited Create(True);
  CS_Threads := TCriticalSection.Create;
  threads := TFavoriteThreadList.Create;
end;

destructor TFavoriteTask.Destroy;
begin
  threads.Free;
  CS_Threads.Free;
  inherited Destroy;
end;

procedure TFavoriteTask.UpdateBtnCaption(Cap: String);
begin
  FBtnCaption := Cap;
  Synchronize(SyncUpdateBtnCaption);
end;

// ----- TFavoriteThread -----

constructor TFavoriteThread.Create;
begin
  inherited Create(True);
  getInfo := TMangaInformation.Create;
  getInfo.FHTTP.Sock.OnHeartbeat := SockOnHeartBeat;
  getInfo.FHTTP.Sock.HeartbeatRate := SOCKHEARTBEATRATE;
  getInfo.isGetByUpdater := False;
end;

destructor TFavoriteThread.Destroy;
begin
  getInfo.Free;
  task.CS_Threads.Acquire;
  try
    task.threads.Remove(Self);
  finally
    task.CS_Threads.Release;
  end;
  inherited Destroy;
end;

procedure TFavoriteThread.SockOnHeartBeat(Sender: TObject);
begin
  if Terminated then
  begin
    TBlockSocket(Sender).Tag := 1;
    TBlockSocket(Sender).StopFlag := True;
    TBlockSocket(Sender).AbortSocket;
  end;
end;

procedure TFavoriteThread.Execute;
begin
  try
    getInfo.mangaInfo.title := manager.favoriteInfo[workCounter].title;
    getInfo.GetInfoFromURL(manager.favoriteInfo[workCounter].Website,
      manager.favoriteInfo[workCounter].Link, manager.DLManager.retryConnect);
    manager.mangaInfo[workCounter] := TMangaInfo.Create;
    TransferMangaInfo(manager.mangaInfo[workCounter], getInfo.mangaInfo);
  except
    on E: Exception do
      MainForm.ExceptionHandler(Self, E);
  end;
end;

// ----- TFavoriteManager -----

procedure TFavoriteManager.MoveLeft(const pos: Cardinal);
var
  i: Cardinal;
begin
  if pos < Count - 1 then
    for i := pos + 1 to Count - 1 do
      favoriteInfo[i - 1] := favoriteInfo[i];
end;

procedure TFavoriteManager.MoveRight(const pos : Cardinal);
var
  i: Cardinal;
begin
  if pos < Count - 1 then
    for i := Count - 1 downto pos + 1 do
      favoriteInfo[i] := favoriteInfo[i - 1];
end;

// ----- public methods -----

constructor TFavoriteManager.Create;
begin
  inherited Create;
  numberOfThreads := 4;
  isRunning := False;
  favorites := TIniFile.Create(WORK_FOLDER + FAVORITES_FILE);
  favorites.CacheUpdates := True;
  Restore;
end;

destructor TFavoriteManager.Destroy;
var
  i: Integer;
begin
  Backup;
  favorites.UpdateFile;
  favorites.Free;
  SetLength(favoriteInfo, 0);
  if Length(mangaInfo) > 0 then
    for i := Low(mangaInfo) to High(mangaInfo) do
      try
        mangaInfo[i].Free;
      except
      end;
  SetLength(mangaInfo, 0);
  inherited Destroy;
end;

procedure TFavoriteManager.Run;
begin
  try
    if (not isAuto) and ((isRunning) or (MainForm.SilentThreadManager.ItemCount > 0)) then
    begin
      MessageDlg('', stDlgFavoritesIsRunning,
        mtInformation, [mbOK], 0);
      Exit;
    end
    else
    if (isAuto) and ((isRunning) or (MainForm.SilentThreadManager.ItemCount > 0)) then
      Exit;
    if Count = 0 then
      Exit;
    MainForm.btFavoritesCheckNewChapter.Caption := stFavoritesChecking;
    isRunning := True;

    CountBeforeChecking := Count;
    SetLength(mangaInfo, Count);

    taskthread := TFavoriteTask.Create;
    taskthread.manager := Self;
    taskthread.Start;
  except
    on E: Exception do
      MainForm.ExceptionHandler(Self, E);
  end;
end;

procedure TFavoriteManager.ShowResult;
var
  numberOfNewChapters: Cardinal = 0;
  l: TStringList;
  newChapterURLList, newChapterNameList: array of TStringList;
  // Store the element position - For chapter folder name.
  newChapterElementPositionList: array of TCardinalList;

  // Check if a string is exists a list
  function Check(list: TStringList; s: String): Boolean;
  var
    i: Cardinal;
  begin
    Result := False;
    if list.Count > 0 then
      for i := 0 to list.Count - 1 do
      begin
        if (Trim(l.Strings[i]) = '') or (CompareText(list.Strings[i], s) = 0) then
        begin
          Result := True;
          Break;
        end;
      end;
  end;

  // Free all used memory when the checking is done
  procedure FreeBuffers;
  var
    i: Cardinal;
  begin
    isRunning := False;
    // Remove completed mangas.
    RemoveCompletedMangas;
    for i := 0 to CountBeforeChecking - 1 do
    begin
      mangaInfo[i].Free;
      if (newChapterURLList[i] <> nil) and
        (newChapterNameList[i] <> nil) then
      begin
        newChapterURLList[i].Free;
        newChapterNameList[i].Free;
        newChapterElementPositionList[i].Free;
      end;
    end;
    SetLength(newChapterURLList, 0);
    SetLength(newChapterNameList, 0);
    SetLength(newChapterElementPositionList, 0);
    SetLength(mangaInfo, 0);
    l.Free;
  end;

var
  s: String;
  i, j, k, pos: Cardinal;
  isDownloadNow: Boolean;
  mangaInfoPtr: PMangaInfo;
  favoriteInfoPtr: PFavoriteInfo;
  LNCResult: TNewChapterResult;
  // Notification dialog.
  notificationDlg: TNewChapter;
  // A string that contains the title of completed mangas, uses for notification.
  removeListStr: String = '';
  // A string that contains the title of mangas that have new chapters,
  // uses for notification.
  newChapterListStr: String = '';

  oldChapterCount, newChapterCount: Integer;

begin
  try
    MainForm.btFavoritesCheckNewChapter.Caption := stFavoritesCheck;

    // Allocate necessary buffers.
    l := TStringList.Create;
    SetLength(newChapterURLList, CountBeforeChecking);
    SetLength(newChapterNameList, CountBeforeChecking);
    SetLength(newChapterElementPositionList, CountBeforeChecking);

    // We must perform a scan to see if there's any new chapter.
    for i := 0 to CountBeforeChecking - 1 do
    begin
      mangaInfoPtr := @mangaInfo[i];
      favoriteInfoPtr := @favoriteInfo[i];

      l.Clear;
      // Get the curent downloaded chapter list by extracting from
      // favorites.ini
      GetParams(l, favoriteInfoPtr^.downloadedChapterList);

      // After the checking, if this manga have any chapter url, then we will perform
      // a comparsion between the "downloadedChapterList" and the newest chapter url list
      // to see if there's any url that doesn't exists in the "downloadedChapterList".
      // Those new urls are new chapters.
      if mangaInfoPtr^.chapterLinks.Count > 0 then
      begin
        for j := 0 to mangaInfo[i].chapterLinks.Count - 1 do
        begin
          if (mangaInfo[i].chapterLinks.Strings[j] <> '') and
            (not Check(l, mangaInfo[i].chapterLinks.Strings[j])) then
          begin
            // We've found a new chapter...
            if (newChapterURLList[i] = nil) or
              (newChapterNameList[i] = nil) then
            begin
              Inc(numberOfNewChapters);
              newChapterElementPositionList[i] := TCardinalList.Create;
              newChapterURLList[i] := TStringList.Create;
              newChapterNameList[i] := TStringList.Create;
            end;
            newChapterElementPositionList[i].Add(j);
            newChapterURLList[i].Add(mangaInfo[i].chapterLinks.Strings[j]);
            newChapterNameList[i].Add(mangaInfo[i].chapterName.Strings[j]);
          end;
        end;

        // Here we construct notification string.
        if (newChapterURLList[i] <> nil) and
          (newChapterNameList[i] <> nil) then
        begin
          newChapterListStr :=
            newChapterListStr + #13 + '- ' + Format(stFavoritesHasNewChapter,
            [favoriteInfo[i].title, favoriteInfo[i].Website, newChapterURLList[i].Count]);
        end;
      end;

      // After each loop, we will generate the string that contains completed
      // manga titles.
      if (OptionAutoRemoveCompletedManga) and (mangaInfo[i].status = '0') then
      begin
        if removeListStr = '' then
          removeListStr := #13#13 + stDlgRemoveCompletedManga;
        removeListStr := removeListStr + #13 + '- ' + favoriteInfo[i].title +
          ' <' + mangaInfo[i].Website + '> ';
      end;
    end;

    if (numberOfNewChapters = 0) then
    begin
      // If there's no new chapter, but there're completed mangas and the user want
      // to notify about them, then we will show the dialog contains the list of
      // completed mangas.
      if (removeListStr <> '') and (isShowDialog) then
      begin
        notificationDlg := TNewChapter.Create(MainForm);
        notificationDlg.lbNotification.Caption :=
          Format(stDlgHasNewChapter, [numberOfNewChapters]);
        notificationDlg.mmMemo.Lines.Add(TrimLeft(removeListStr));
        notificationDlg.btDownload.Visible := False;
        notificationDlg.btQueue.Visible := False;
        notificationDlg.ShowModal;
        LNCResult := notificationDlg.FormResult;
        notificationDlg.Free;
      end;
    end
    else
    //give an option to straight download or not
    if OptionAutoDlFav then
    begin
      isDownloadNow := True;
    end
    else
      // There're new chapters, we need to process them ...
    begin
      if isShowDialog then
      begin
        notificationDlg := TNewChapter.Create(MainForm);
        notificationDlg.lbNotification.Caption :=
          Format(stDlgHasNewChapter, [numberOfNewChapters]);
        notificationDlg.mmMemo.Lines.Add(
          TrimLeft(newChapterListStr) + #13#13 + TrimLeft(removeListStr));
        notificationDlg.ShowModal;
        LNCResult := notificationDlg.FormResult;
        notificationDlg.Free;

        if LNCResult = ncrDownload then
        begin
          isDownloadNow := True;
          if MainForm.pcMain.PageIndex <> 0 then
            MainForm.pcMain.PageIndex := 0;
        end
        else
        if LNCResult = ncrQueue then
          isDownloadNow := False
        else
        begin
          FreeBuffers;
          Exit;
        end;
      end;
    end;

    // Now we do the download task generator ...
    while DLManager.isRunningBackup do
      Sleep(64);
    DLManager.isRunningBackup := True;
    for i := 0 to CountBeforeChecking - 1 do
    begin
      if (newChapterURLList[i] <> nil) and
        (newChapterNameList[i] <> nil) then
      begin
        mangaInfoPtr := @mangaInfo[i];
        favoriteInfoPtr := @favoriteInfo[i];
        // generate a new download task.
        DLManager.AddTask;
        pos := DLManager.containers.Count - 1;
        DLManager.containers.Items[pos].MangaSiteID :=
          GetMangaSiteID(mangaInfoPtr^.website);
        if newChapterURLList[i].Count > 0 then
        begin
          for j := 0 to newChapterURLList[i].Count - 1 do
          begin
            s := CustomRename(OptionCustomRename,
              mangaInfoPtr^.website,
              favoriteInfoPtr^.title,
              mangaInfoPtr^.authors,
              mangaInfoPtr^.artists,
              newChapterNameList[i].Strings[j],
              Format('%.4d', [newChapterElementPositionList[i].Items[j] + 1]),
              MainForm.cbOptionPathConvert.Checked);
            DLManager.containers.Items[pos].ChapterName.Add(s);
            DLManager.containers.Items[pos].ChapterLinks.Add(
              newChapterURLList[i].Strings[j]);
          end;
        end;
        if not isDownloadNow then
        begin
          DLManager.containers.Items[pos].DownloadInfo.Status := stStop;
          DLManager.containers.Items[pos].Status := STATUS_STOP;
        end
        else
        begin
          DLManager.containers.Items[pos].DownloadInfo.Status := stWait;
          DLManager.containers.Items[pos].Status := STATUS_WAIT;
        end;
        DLManager.containers.Items[pos].CurrentDownloadChapterPtr := 0;
        DLManager.containers.Items[pos].DownloadInfo.title := favoriteInfoPtr^.title;
        DLManager.containers.Items[pos].DownloadInfo.Website := favoriteInfoPtr^.website;
        DLManager.containers.Items[pos].DownloadInfo.SaveTo := favoriteInfoPtr^.SaveTo;
        DLManager.containers.Items[pos].DownloadInfo.dateTime := Now;

        favoriteInfoPtr^.currentChapter := IntToStr(mangaInfoPtr^.numChapter);
        Sleep(4);
        // End - generate a new download task.

        // Mark these new chapters as downloaded.
        if mangaInfo[i].chapterLinks.Count = 0 then
          continue;
        oldChapterCount := StrToInt(favoriteInfoPtr^.currentChapter);
        newChapterCount := mangaInfo[i].chapterLinks.Count;
        if oldChapterCount < newChapterCount - 1 then
        begin
          s := '';
          for k := oldChapterCount to newChapterCount - 1 do
            s := s + IntToStr(k) + SEPERATOR;
          if s <> '' then
            DLManager.AddToDownloadedChaptersList(favoriteInfo[i].website +
              favoriteInfo[i].link, s);
        end;
      end;
    end;
    DLManager.isRunningBackup := False;

    if Assigned(OnUpdateDownload) then
    begin
      //MainForm.DLManager.Sort(MainForm.vtDownload.Header.SortColumn);
      OnUpdateDownload;
    end;
    if isDownloadNow then
    begin
      DLManager.CheckAndActiveTask;
      Sleep(64);
      DLManager.Backup;
    end;

    // Update favorites's downloaded chapter list.
    for i := 0 to CountBeforeChecking - 1 do
    begin
      if mangaInfo[i].numChapter > 0 then
      begin
        if Trim(mangaInfo[i].chapterLinks.Text) = '' then
          continue;
        favoriteInfo[i].currentChapter := IntToStr(mangaInfo[i].numChapter);
        favoriteInfo[i].downloadedChapterList := '';
        for j := 0 to mangaInfo[i].numChapter - 1 do
          favoriteInfo[i].downloadedChapterList :=
            favoriteInfo[i].downloadedChapterList + mangaInfo[i].chapterLinks.Strings[j] +
            SEPERATOR;
      end;
    end;

    FreeBuffers;
    if Assigned(OnUpdateFavorite) then
      OnUpdateFavorite;

    // Save new result to favorites.ini.
    Backup;
  except
    on E: Exception do
      MainForm.ExceptionHandler(Self, E);
  end;
end;

procedure TFavoriteManager.RemoveCompletedMangas;
// This method should be used in ShowResult().
var
  i, j: Cardinal;
begin
  i := 0;
  j := 0;
  if OptionAutoRemoveCompletedManga then
  begin
    while i < CountBeforeChecking do
    begin
      if mangaInfo[j].status = '0' then
      begin
        Remove(i);
        Dec(CountBeforeChecking);
      end
      else
        Inc(i);
      Inc(j);
    end;
  end;
end;

function TFavoriteManager.IsMangaExist(const title, website: String): Boolean;
var
  i: Integer;
begin
  if Length(favoriteInfo) > 0 then
    for i := Low(favoriteInfo) to High(favoriteInfo) do
      if (CompareText(favoriteInfo[i].title, title) = 0) and
        (CompareText(favoriteInfo[i].website, website) = 0) then
        Exit(True);
  Result := False;
end;

function TFavoriteManager.IsMangaExistURL(const website, URL : String): Boolean;
Var
  i: Integer;
begin
  Result := False;
  if Length(favoriteInfo) > 0 then
    for i := Low(favoriteInfo) to High(favoriteInfo) do
      if SameText(website, favoriteInfo[i].Website) and
        SameText(URL, favoriteInfo[i].Link) then
        Exit(True);
  Result := False;
end;

procedure TFavoriteManager.Add(
  const title, currentChapter, downloadedChapterList, website, saveTo, link: String);
begin
  try
    if IsMangaExist(title, website) then
      Exit;
    Inc(Count);
    SetLength(favoriteInfo, Count);
    favoriteInfo[Count - 1].title := title;
    favoriteInfo[Count - 1].currentChapter := currentChapter;
    favoriteInfo[Count - 1].website := website;
    favoriteInfo[Count - 1].saveTo := saveTo;
    favoriteInfo[Count - 1].Link := Link;
    favoriteInfo[Count - 1].downloadedChapterList := downloadedChapterList;
    if ((MainForm.SilentThreadManager.ItemCount <= 2) or (Random(50) = 0)) and
      (not isRunning) then
    begin
      Sort(sortColumn);
      Backup;
    end;
  except
    on E: Exception do
      MainForm.ExceptionHandler(Self, E);
  end;
end;

procedure TFavoriteManager.AddMerge(
  const title, currentChapter, downloadedChapterList, website, saveTo, link: String);
begin
  try
    if IsMangaExist(title, website) then
      Exit;
    Inc(Count);
    SetLength(favoriteInfo, Count);
    favoriteInfo[Count - 1].title := title;
    favoriteInfo[Count - 1].currentChapter := currentChapter;
    favoriteInfo[Count - 1].website := website;
    favoriteInfo[Count - 1].saveTo := saveTo;
    favoriteInfo[Count - 1].Link := Link;
    favoriteInfo[Count - 1].downloadedChapterList := downloadedChapterList;
  except
    on E: Exception do
      MainForm.ExceptionHandler(Self, E);
  end;
end;

procedure TFavoriteManager.MergeWith(const APath: String);
var
  mergeFile: TIniFile;
  fstream: TFileStreamUTF8;
  l, i: Cardinal;
  infos: array of TFavoriteInfo;
begin
  if isRunning then
    Exit;
  if not FileExistsUTF8(APath) then
    Exit;
  isRunning := True;

  fstream := TFileStreamUTF8.Create(APath, fmOpenRead);
  mergeFile := TIniFile.Create(fstream);

  l := mergeFile.ReadInteger('general', 'NumberOfFavorites', 0);
  if l > 0 then
  begin
    SetLength(infos, l);
    for i := 0 to l - 1 do
    begin
      infos[i].title := mergeFile.ReadString(IntToStr(i), 'Title', '');
      infos[i].currentChapter :=
        mergeFile.ReadString(IntToStr(i), 'CurrentChapter', '0');
      infos[i].downloadedChapterList :=
        mergeFile.ReadString(IntToStr(i), 'DownloadedChapterList', '');
      infos[i].website := mergeFile.ReadString(IntToStr(i), 'Website', '');
      infos[i].SaveTo := mergeFile.ReadString(IntToStr(i), 'SaveTo', '');
      infos[i].link := mergeFile.ReadString(IntToStr(i), 'Link', '');

      AddMerge(infos[i].title,
        infos[i].currentChapter,
        infos[i].downloadedChapterList,
        infos[i].website,
        infos[i].SaveTo,
        infos[i].link);
    end;
  end;
  Sort(sortColumn);
  Backup;

  SetLength(infos, 0);
  fStream.Free;
  mergeFile.Free;
  isRunning := False;
end;

procedure TFavoriteManager.Remove(const pos: Cardinal; const isBackup: Boolean = True);
begin
  if isRunning then
    Exit;
  if pos >= Count then
    Exit;
  MoveLeft(pos);
  SetLength(favoriteInfo, Count - 1);
  Dec(Count);
  if isBackup then
    Backup;
end;

procedure TFavoriteManager.Restore;
var
  i: Cardinal;
begin
  Count := favorites.ReadInteger('general', 'NumberOfFavorites', 0);
  SetLength(favoriteInfo, Count);
  if Length(favoriteInfo) = 0 then
    Exit;
  for i := 0 to Length(favoriteInfo) - 1 do
  begin
    favoriteInfo[i].title := favorites.ReadString(IntToStr(i), 'Title', '');
    favoriteInfo[i].currentChapter :=
      favorites.ReadString(IntToStr(i), 'CurrentChapter', '0');
    favoriteInfo[i].downloadedChapterList :=
      favorites.ReadString(IntToStr(i), 'DownloadedChapterList', '');
    favoriteInfo[i].website := favorites.ReadString(IntToStr(i), 'Website', '');
    favoriteInfo[i].SaveTo :=
      CorrectPathSys(favorites.ReadString(IntToStr(i), 'SaveTo', ''));
    favoriteInfo[i].link := favorites.ReadString(IntToStr(i), 'Link', '');
  end;
end;

procedure TFavoriteManager.Backup;
var
  i: Cardinal;
begin
  // delete old info
  if favorites.ReadInteger('general', 'NumberOfFavorites', 0) > 0 then
    for i := 0 to favorites.ReadInteger('general', 'NumberOfFavorites', 0) - 1 do
      favorites.EraseSection(IntToStr(i));

  favorites.WriteInteger('general', 'NumberOfFavorites', Length(favoriteInfo));
  if Length(favoriteInfo) > 0 then
    for i := 0 to Length(favoriteInfo) - 1 do
    begin
      favorites.WriteString(IntToStr(i), 'Title', favoriteInfo[i].title);
      favorites.WriteString(IntToStr(i), 'CurrentChapter',
        favoriteInfo[i].currentChapter);
      favorites.WriteString(IntToStr(i), 'DownloadedChapterList',
        favoriteInfo[i].downloadedChapterList);
      favorites.WriteString(IntToStr(i), 'Website', favoriteInfo[i].Website);
      favorites.WriteString(IntToStr(i), 'SaveTo', favoriteInfo[i].SaveTo);
      favorites.WriteString(IntToStr(i), 'Link', favoriteInfo[i].link);
    end;
  favorites.UpdateFile;
end;

procedure TFavoriteManager.StopAllAndWait;
var
  i: Integer;
begin
  if isRunning then
  begin
    taskthread.Terminate;
    if taskthread.threads.Count > 0 then
    begin
      taskthread.CS_Threads.Acquire;
      try
        for i := 0 to taskthread.threads.Count - 1 do
          taskthread.threads[i].Terminate;
      finally
        taskthread.CS_Threads.Release;
      end;
    end;
    taskthread.WaitFor;
  end;
end;

procedure TFavoriteManager.Sort(const AColumn: Cardinal);

  function GetStr(const ARow: Cardinal): String;
  begin
    case AColumn of
      1: Result := favoriteInfo[ARow].title;
      2: Result := favoriteInfo[ARow].currentChapter;
      3: Result := favoriteInfo[ARow].website;
      4: Result := favoriteInfo[ARow].SaveTo;
    end;
  end;

  procedure QSort(L, R: Cardinal);
  var
    i, j: Cardinal;
    X: String;
    tmp: TFavoriteInfo;
  begin
    X := GetStr((L + R) div 2);
    i := L;
    j := R;
    while i <= j do
    begin
      case sortDirection of
        False:
        begin
          case AColumn of
            2:
            begin
              while StrToInt(GetStr(i)) < StrToInt(X) do
                Inc(i);
              while StrToInt(GetStr(j)) > StrToInt(X) do
                Dec(j);
            end
            else
            begin
              while StrComp(PChar(GetStr(i)), PChar(X)) < 0 do
                Inc(i);
              while StrComp(PChar(GetStr(j)), PChar(X)) > 0 do
                Dec(j);
            end;
          end;
        end;
        True:
        begin
          case AColumn of
            2:
            begin
              while StrToInt(GetStr(i)) > StrToInt(X) do
                Inc(i);
              while StrToInt(GetStr(j)) < StrToInt(X) do
                Dec(j);
            end
            else
            begin
              while StrComp(PChar(GetStr(i)), PChar(X)) > 0 do
                Inc(i);
              while StrComp(PChar(GetStr(j)), PChar(X)) < 0 do
                Dec(j);
            end;
          end;
        end;
      end;
      if i <= j then
      begin
        tmp := favoriteInfo[i];
        favoriteInfo[i] := favoriteInfo[j];
        favoriteInfo[j] := tmp;
        Inc(i);
        if j > 0 then
          Dec(j);
      end;
    end;
    if L < j then
      QSort(L, j);
    if i < R then
      QSort(i, R);
  end;

begin
  sortColumn := AColumn;
  QSort(0, Length(favoriteInfo) - 1);
end;

procedure TFavoriteManager.SortNatural(const AColumn: Integer);

  function Swap(const id1, id2: Integer): Boolean;
  var
    tmp: TFavoriteInfo;
  begin
    if (id1 >= Length(favoriteInfo)) or (id2 >= Length(favoriteInfo)) then
      Exit(False);
    tmp := favoriteInfo[id1];
    favoriteInfo[id1] := favoriteInfo[id2];
    favoriteInfo[id2] := tmp;
    Result := True;
  end;

  function GetStr(const ARow: Cardinal): String;
  begin
    case AColumn of
      1: Result := favoriteInfo[ARow].title;
      2: Result := favoriteInfo[ARow].currentChapter;
      3: Result := favoriteInfo[ARow].website;
      4: Result := favoriteInfo[ARow].SaveTo;
      else
        Result := '';
    end;
  end;

  procedure QuickSortA(L, R: Integer);
  var
    Pivot, vL, vR: Integer;
    PivotStr: String;
  begin
    if R - L <= 1 then
    begin // a little bit of time saver
      if L < R then
        if SortDirection then
          if AnsiNaturalCompare(GetStr(L), GetStr(R)) > 0 then
            Swap(L, R)
          else
          if AnsiNaturalCompare(GetStr(L), GetStr(R)) < 0 then
            Swap(L, R);
      Exit;
    end;
    vL := L;
    vR := R;
    Pivot := L + Random(R - L); // they say random is best
    PivotStr := GetStr(Pivot);
    while vL < vR do
    begin
      if SortDirection then
      begin
        while (vL < Pivot) and (AnsiNaturalCompare(GetStr(vL), PivotStr) > 0) do
          Inc(vL);
        while (vR > Pivot) and (AnsiNaturalCompare(GetStr(vR), PivotStr) <= 0) do
          Dec(vR);
      end
      else
      begin
        while (vL < Pivot) and (AnsiNaturalCompare(GetStr(vL), PivotStr) <= 0) do
          Inc(vL);
        while (vR > Pivot) and (AnsiNaturalCompare(GetStr(vR), PivotStr) > 0) do
          Dec(vR);
      end;
      Swap(vL, vR);
      if Pivot = vL then // swap pivot if we just hit it from one side
      begin
        Pivot := vR;
        PivotStr := GetStr(Pivot);
      end
      else
      if Pivot = vR then
      begin
        Pivot := vL;
        PivotStr := GetStr(Pivot);
      end;
    end;
    if Pivot - 1 >= L then
      QuickSortA(L, Pivot - 1);
    if Pivot + 1 <= R then
      QuickSortA(Pivot + 1, R);
  end;

begin
  sortColumn := AColumn;
  QuickSortA(0, Length(favoriteInfo) - 1);
end;

end.
