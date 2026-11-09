#import "AddonManager.h"
#import "AddonBrowser.h"
#import "../App/WKLocalization.h"
#import "../App/WolkaraForeverTheme.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface TKWoWAddon ()
@property(nonatomic, readwrite, copy) NSString *folder;
@property(nonatomic, readwrite, copy) NSString *title;
@property(nonatomic, readwrite, copy, nullable) NSString *version;
@property(nonatomic, readwrite) NSUInteger fileCount;
@end

@implementation TKWoWAddon
@end

static NSString *TOCValue(NSString *text, NSString *key) {
    NSString *prefix=[@"## " stringByAppendingString:key];
    for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        if (![line hasPrefix:prefix]) continue;
        NSString *value=[[line substringFromIndex:prefix.length] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (value.length && value.length<=512) return value;
    }
    return nil;
}

static NSString *ReadTOC(NSString *directory, NSString *folder) {
    NSArray<NSString *> *names=[[NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:NULL] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    NSString *preferred=[folder stringByAppendingPathExtension:@"toc"];
    for (NSString *name in names) {
        if (![name.pathExtension.lowercaseString isEqual:@"toc"]) continue;
        if (![name isEqual:preferred] && [names containsObject:preferred]) continue;
        NSString *text=TKAddonReadTOCHeader([directory stringByAppendingPathComponent:name]);
        if (text) return text;
    }
    return nil;
}

NSArray<TKWoWAddon *> *TKWoWAddonsAtDirectory(NSString *directory) {
    NSFileManager *manager=NSFileManager.defaultManager;
    NSArray<NSString *> *names=[[manager contentsOfDirectoryAtPath:directory error:NULL] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    NSMutableArray<TKWoWAddon *> *addons=[NSMutableArray new];
    for (NSString *name in names) {
        if (!name.length || [name hasPrefix:@"."]) continue;
        NSString *path=[directory stringByAppendingPathComponent:name];
        NSURL *url=[NSURL fileURLWithPath:path]; NSNumber *directoryValue=nil;
        if (![url getResourceValue:&directoryValue forKey:NSURLIsDirectoryKey error:NULL] || !directoryValue.boolValue) continue;
        NSString *toc=ReadTOC(path,name);
        if (!toc) continue;
        NSDirectoryEnumerator *files=[manager enumeratorAtURL:[NSURL fileURLWithPath:path] includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles|NSDirectoryEnumerationSkipsPackageDescendants errorHandler:nil];
        NSUInteger count=0; while ([files nextObject]) count++;
        TKWoWAddon *addon=[TKWoWAddon new]; addon.folder=name;
        addon.title=TOCValue(toc,@"Title:")?:name;
        addon.version=TOCValue(toc,@"Version:"); addon.fileCount=count;
        [addons addObject:addon];
    }
    return addons;
}


@interface TKWoWAddonManagerViewController () <UIDocumentPickerDelegate>
@property(nonatomic,copy) NSString *installedGameVersion, *addOnsDirectory, *edition, *product;
@property(nonatomic) TKAddonStore *store;
@property(nonatomic) BOOL writing, previousPopEnabled, previousModal;
@property(nonatomic) UILabel *status;
@property(nonatomic) UIButton *browseButton;
@property(nonatomic) UIStackView *headerStack;
@end

@implementation TKWoWAddonManagerViewController
- (instancetype)initWithAddOnsDirectory:(NSString *)directory edition:(NSString *)edition {
    return [self initWithAddOnsDirectory:directory edition:edition product:@"" gameVersion:@""];
}
- (instancetype)initWithAddOnsDirectory:(NSString *)directory edition:(NSString *)edition product:(NSString *)product gameVersion:(NSString *)version {
    if (!(self=[super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    NSArray *parts=[version componentsSeparatedByString:@"."];
    _installedGameVersion=parts.count>=3 ? [[parts subarrayWithRange:NSMakeRange(0,3)] componentsJoinedByString:@"."] : @"";
    _addOnsDirectory=directory.copy; _edition=edition.copy; _product=product.copy;
    _store=[[TKAddonStore alloc] initWithAddOnsDirectory:directory product:product gameVersion:_installedGameVersion];
    self.title=WKLocalized(@"addons.title");
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.tableView.backgroundColor=WKInk(); self.tableView.rowHeight=UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight=78; self.tableView.accessibilityIdentifier=@"wow.addons";
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:WKLocalized(@"common.done") style:UIBarButtonItemStylePlain target:self action:@selector(done)];
    UIBarButtonItem *add=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(importAddon)];
    add.accessibilityIdentifier=@"wow.addons.import"; add.accessibilityLabel=WKLocalized(@"addons.web.importZIP");
    UIBarButtonItem *refresh=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reloadAddons)];
    refresh.accessibilityIdentifier=@"wow.addons.refresh";
    self.navigationItem.rightBarButtonItems=@[add,refresh];
    UILabel *edition=WKLabel(17,UIFontWeightSemibold,WKGold());
    edition.text=[NSString stringWithFormat:@"%@ · %@",_edition,_installedGameVersion];
    _browseButton=[UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *configuration=UIButtonConfiguration.filledButtonConfiguration;
    configuration.title=WKLocalized(@"addons.web.browse");
    configuration.image=[UIImage systemImageNamed:@"globe"];
    configuration.imagePadding=10; configuration.baseBackgroundColor=WKGold(); configuration.baseForegroundColor=WKOnGold();
    configuration.contentInsets=NSDirectionalEdgeInsetsMake(12,16,12,16);
    _browseButton.configuration=configuration; _browseButton.accessibilityIdentifier=@"wow.addons.browse";
    [_browseButton addTarget:self action:@selector(browseCurseForge) forControlEvents:UIControlEventTouchUpInside];
    _status=WKNote(WKLocalized(@"addons.web.managerHint")); _status.accessibilityIdentifier=@"wow.addons.status";
    _headerStack=[[UIStackView alloc] initWithArrangedSubviews:@[edition,_browseButton,_status]];
    _headerStack.axis=UILayoutConstraintAxisVertical; _headerStack.spacing=12;
    _headerStack.layoutMargins=UIEdgeInsetsMake(12,20,16,20); _headerStack.layoutMarginsRelativeArrangement=YES;
    self.tableView.tableHeaderView=_headerStack;
    [self reloadAddons];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width=self.tableView.bounds.size.width;
    CGSize size=[_headerStack systemLayoutSizeFittingSize:CGSizeMake(width,UILayoutFittingCompressedSize.height)
        withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    if (fabs(_headerStack.frame.size.width-width)>0.5 || fabs(_headerStack.frame.size.height-size.height)>0.5) {
        _headerStack.frame=CGRectMake(0,0,width,size.height); self.tableView.tableHeaderView=_headerStack;
    }
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _previousPopEnabled=self.navigationController.interactivePopGestureRecognizer.enabled;
    _previousModal=self.navigationController.modalInPresentation;
    [self reloadAddons]; [self updateControls];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.navigationController.interactivePopGestureRecognizer.enabled=_previousPopEnabled;
    self.navigationController.modalInPresentation=_previousModal;
}
- (void)updateControls {
    self.navigationItem.leftBarButtonItem.enabled=!_writing;
    self.navigationItem.hidesBackButton=_writing;
    for (UIBarButtonItem *item in self.navigationItem.rightBarButtonItems) item.enabled=!_writing;
    self.modalInPresentation=_writing;
    self.navigationController.modalInPresentation=_writing || _previousModal;
    self.navigationController.interactivePopGestureRecognizer.enabled=!_writing && _previousPopEnabled;
    self.tableView.userInteractionEnabled=!_writing;
}
- (void)done { if (!_writing) WKDismissPage(self); }
- (void)reloadAddons {
    if (_writing) return;
    [NSFileManager.defaultManager createDirectoryAtPath:_addOnsDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
    [_store reload]; [self.tableView reloadData];
}
- (void)browseCurseForge {
    if (_writing) return;
    TKAddonBrowserViewController *browser=[[TKAddonBrowserViewController alloc] initWithURL:TKAddonBrowseURL(_product) edition:_edition];
    __weak TKWoWAddonManagerViewController *weakSelf=self;
    browser.installArchive=^(NSURL *url,void (^completion)(NSError *)) {
        TKWoWAddonManagerViewController *self=weakSelf;
        if (!self) { completion([NSError errorWithDomain:@"Wolkara.Addons" code:1 userInfo:@{NSLocalizedDescriptionKey:WKLocalized(@"addons.error.importMessage")}]); return; }
        [self installArchiveAtURL:url completion:completion];
    };
    [self.navigationController pushViewController:browser animated:YES];
}
- (void)installArchiveAtURL:(NSURL *)url completion:(void (^)(NSError *))completion {
    if (_writing) { completion([NSError errorWithDomain:@"Wolkara.Addons" code:1 userInfo:@{NSLocalizedDescriptionKey:WKLocalized(@"addons.web.installing")}]); return; }
    _writing=YES; _status.text=WKLocalized(@"addons.web.installing"); [self updateControls];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        @autoreleasepool {
            TKAddonStore *worker=[[TKAddonStore alloc] initWithAddOnsDirectory:self.addOnsDirectory product:self.product gameVersion:self.installedGameVersion];
            NSError *error=nil;
            if (![worker installZIPAtURL:url error:&error] && !error)
                error=[NSError errorWithDomain:@"Wolkara.Addons" code:1 userInfo:@{NSLocalizedDescriptionKey:WKLocalized(@"addons.error.importMessage")}];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.writing=NO;
                self.status.text=error.localizedDescription ?: WKLocalized(@"addons.web.installed");
                [self reloadAddons];
                // The browser owns the navigation guard while it is visible.
                if (self.navigationController.topViewController==self) [self updateControls];
                completion(error);
            });
        }
    });
}
- (void)importAddon {
    if (_writing) return;
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeZIP] asCopy:YES];
    picker.allowsMultipleSelection=NO; picker.delegate=self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller; NSURL *url=urls.firstObject; if (!url) return;
    BOOL accessed=[url startAccessingSecurityScopedResource];
    [self installArchiveAtURL:url completion:^(NSError *error) {
        if (accessed) [url stopAccessingSecurityScopedResource];
        if (error) [self presentError:error];
    }];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section; return _store.records.count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView; (void)section; return WKLocalizedFormat(@"addons.mode.installed",(unsigned long)_store.records.count);
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section; return WKLocalized(@"addons.web.footer");
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"addon"];
    if (!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"addon"];
    TKAddonRecord *record=_store.records[indexPath.row];
    cell.textLabel.text=record.name; cell.textLabel.textColor=WKGold(); cell.textLabel.numberOfLines=0;
    NSMutableArray *details=[NSMutableArray arrayWithObjects:record.version ?: @"",
        WKLocalized(record.disabled?@"addons.state.disabled":(record.managed?@"addons.state.managed":@"addons.source.existing")),nil];
    if (record.pinned) [details addObject:WKLocalized(@"addons.state.pinnedShort")];
    if ([record.compatibility isEqual:TKAddonCompatibilityUnverified]) [details addObject:WKLocalized(@"addons.state.notVerifiedForForever")];
    cell.detailTextLabel.text=[details componentsJoinedByString:@" · "];
    cell.detailTextLabel.numberOfLines=0; cell.detailTextLabel.textColor=WKMuted();
    cell.backgroundColor=WKPanel(); cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES]; if (_writing) return;
    UIAlertController *sheet=[self manageSheetForRecord:_store.records[indexPath.row]];
    sheet.popoverPresentationController.sourceView=tableView;
    sheet.popoverPresentationController.sourceRect=[tableView rectForRowAtIndexPath:indexPath];
    [self presentViewController:sheet animated:YES completion:nil];
}
- (UIAlertController *)manageSheetForRecord:(TKAddonRecord *)record {
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:record.name message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    if (record.managed) {
        [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(record.disabled?@"addons.restore":@"addons.disable") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            (void)action; [self mutate:^BOOL(NSError **error) { return [self.store setDisabled:!record.disabled record:record error:error]; }];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(record.pinned?@"addons.unpin":@"addons.pin") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            (void)action; [self mutate:^BOOL(NSError **error) { return [self.store setPinned:!record.pinned record:record error:error]; }];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"addons.remove") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        (void)action; [self mutate:^BOOL(NSError **error) { return [self.store removeRecord:record error:error]; }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:WKLocalized(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    return sheet;
}
- (void)mutate:(BOOL (^)(NSError **))operation {
    if (_writing) return;
    NSError *error=nil; if (!operation(&error)) [self presentError:error]; [self reloadAddons];
}
- (void)presentError:(NSError *)error {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:WKLocalized(@"addons.error.importTitle") message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:WKLocalized(@"common.ok") style:UIAlertActionStyleDefault handler:nil]];
    WKPresentWhenFree(self, ^{ [self presentViewController:alert animated:YES completion:nil]; });
}
@end
