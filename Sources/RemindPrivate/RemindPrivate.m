#import "RemindPrivate.h"

#import <dlfcn.h>
#import <objc/runtime.h>
#import <string.h>

static const char *const RPFrameworkPath = "/System/Library/PrivateFrameworks/ReminderKit.framework/ReminderKit";

@interface RPAssignment ()
- (instancetype)initWithAssigneeID:(NSString *)assigneeID
                       displayName:(nullable NSString *)displayName
                         firstName:(nullable NSString *)firstName
                          lastName:(nullable NSString *)lastName
                            status:(NSInteger)status
                      assignedDate:(nullable NSDate *)assignedDate;
@end

@implementation RPAssignment

- (instancetype)initWithAssigneeID:(NSString *)assigneeID
                       displayName:(nullable NSString *)displayName
                         firstName:(nullable NSString *)firstName
                          lastName:(nullable NSString *)lastName
                            status:(NSInteger)status
                      assignedDate:(nullable NSDate *)assignedDate {
  if ((self = [super init])) {
    _assigneeID = [assigneeID copy];
    _displayName = [displayName copy];
    _firstName = [firstName copy];
    _lastName = [lastName copy];
    _status = status;
    _assignedDate = [assignedDate copy];
  }
  return self;
}

@end

@interface RPReminderFields ()
- (instancetype)initWithFlagged:(BOOL)flagged
                        urgent:(BOOL)urgent
                          tags:(NSArray<NSString *> *)tags
        dueDateDeltaAlertsData:(nullable NSData *)dueDateDeltaAlertsData
                      parentID:(nullable NSString *)parentID
                   assignments:(NSArray<RPAssignment *> *)assignments
                         links:(nullable NSArray<NSString *> *)links;
@end

@implementation RPReminderFields

- (instancetype)initWithFlagged:(BOOL)flagged
                        urgent:(BOOL)urgent
                          tags:(NSArray<NSString *> *)tags
        dueDateDeltaAlertsData:(nullable NSData *)dueDateDeltaAlertsData
                      parentID:(nullable NSString *)parentID
                   assignments:(NSArray<RPAssignment *> *)assignments
                         links:(nullable NSArray<NSString *> *)links {
  if ((self = [super init])) {
    _flagged = flagged;
    _urgent = urgent;
    _tags = [tags copy];
    _dueDateDeltaAlertsData = [dueDateDeltaAlertsData copy];
    _parentID = [parentID copy];
    _assignments = [assignments copy];
    _links = [links copy];
  }
  return self;
}

@end

@implementation RPReadResult

- (instancetype)initWithFields:(NSDictionary<NSString *, RPReminderFields *> *)fields
             unavailableReason:(nullable NSString *)unavailableReason {
  if ((self = [super init])) {
    _fields = [fields copy];
    _unavailableReason = [unavailableReason copy];
  }
  return self;
}

@end

@implementation RPEarlyReminderChange

+ (instancetype)removal {
  RPEarlyReminderChange *change = [[self alloc] initWithUnit:0 count:0];
  change->_removes = YES;
  return change;
}

- (instancetype)initWithUnit:(NSInteger)unit count:(NSInteger)count {
  if ((self = [super init])) {
    _unit = unit;
    _count = count;
  }
  return self;
}

@end

@implementation RPReminderChange

- (instancetype)initWithFlagged:(nullable NSNumber *)flagged urgent:(nullable NSNumber *)urgent {
  return [self initWithFlagged:flagged urgent:urgent earlyReminder:nil];
}

- (instancetype)initWithFlagged:(nullable NSNumber *)flagged
                         urgent:(nullable NSNumber *)urgent
                  earlyReminder:(nullable RPEarlyReminderChange *)earlyReminder {
  return [self initWithFlagged:flagged urgent:urgent earlyReminder:earlyReminder tagsToAdd:@[] tagsToRemove:@[]];
}

- (instancetype)initWithFlagged:(nullable NSNumber *)flagged
                         urgent:(nullable NSNumber *)urgent
                  earlyReminder:(nullable RPEarlyReminderChange *)earlyReminder
                      tagsToAdd:(NSArray<NSString *> *)tagsToAdd
                   tagsToRemove:(NSArray<NSString *> *)tagsToRemove {
  return [self initWithFlagged:flagged
                        urgent:urgent
                 earlyReminder:earlyReminder
                     tagsToAdd:tagsToAdd
                  tagsToRemove:tagsToRemove
                    linksToAdd:@[]
                 linksToRemove:@[]];
}

- (instancetype)initWithFlagged:(nullable NSNumber *)flagged
                         urgent:(nullable NSNumber *)urgent
                  earlyReminder:(nullable RPEarlyReminderChange *)earlyReminder
                      tagsToAdd:(NSArray<NSString *> *)tagsToAdd
                   tagsToRemove:(NSArray<NSString *> *)tagsToRemove
                     linksToAdd:(NSArray<NSURL *> *)linksToAdd
                  linksToRemove:(NSArray<NSURL *> *)linksToRemove {
  if ((self = [super init])) {
    _flagged = [flagged copy];
    _urgent = [urgent copy];
    _earlyReminder = earlyReminder;
    _tagsToAdd = [tagsToAdd copy];
    _tagsToRemove = [tagsToRemove copy];
    _linksToAdd = [linksToAdd copy];
    _linksToRemove = [linksToRemove copy];
  }
  return self;
}

@end

@implementation RPWriteResult

- (instancetype)initWithFailureReason:(nullable NSString *)failureReason outcomeUnknown:(BOOL)outcomeUnknown {
  if ((self = [super init])) {
    _failureReason = [failureReason copy];
    _outcomeUnknown = outcomeUnknown;
  }
  return self;
}

@end

static RPReadResult *RPUnavailable(NSString *reason) {
  return [[RPReadResult alloc] initWithFields:@{} unavailableReason:reason];
}

static id _Nullable RPInvokeWithErrorOut(
    id target, NSString *selectorName, __unsafe_unretained id _Nullable const *arguments, NSUInteger argumentCount,
    NSString **reason) {
  SEL selector = NSSelectorFromString(selectorName);
  if (![target respondsToSelector:selector]) {
    *reason = [NSString stringWithFormat:@"REMStore has no %@", selectorName];
    return nil;
  }

  NSMethodSignature *signature = [target methodSignatureForSelector:selector];
  NSUInteger errorIndex = argumentCount + 2;
  BOOL shapeMatches = signature.numberOfArguments == errorIndex + 1
      && strchr(signature.methodReturnType, '@') != NULL
      && strstr([signature getArgumentTypeAtIndex:errorIndex], "^@") != NULL;
  for (NSUInteger index = 0; shapeMatches && index < argumentCount; index++) {
    shapeMatches = strchr([signature getArgumentTypeAtIndex:index + 2], '@') != NULL;
  }
  if (!shapeMatches) {
    *reason = [NSString stringWithFormat:@"REMStore %@ has an unexpected signature", selectorName];
    return nil;
  }

  NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
  invocation.selector = selector;
  for (NSUInteger index = 0; index < argumentCount; index++) {
    __unsafe_unretained id argument = arguments[index];
    [invocation setArgument:&argument atIndex:index + 2];
  }
  NSError *__autoreleasing error = nil;
  NSError *__autoreleasing *errorPointer = &error;
  [invocation setArgument:&errorPointer atIndex:errorIndex];
  [invocation invokeWithTarget:target];

  void *rawResult = NULL;
  [invocation getReturnValue:&rawResult];
  id result = (__bridge id)rawResult;
  if (error != nil) {
    *reason = error.localizedDescription;
    return nil;
  }
  if (result == nil) {
    *reason = [NSString stringWithFormat:@"REMStore %@ returned nothing", selectorName];
  }
  return result;
}

static NSString *_Nullable RPOptionalString(id object, NSString *key) {
  if (![object respondsToSelector:NSSelectorFromString(key)]) {
    return nil;
  }
  id value = [object valueForKey:key];
  return [value isKindOfClass:NSString.class] ? value : nil;
}

static NSArray *RPShareesForReminder(id storage, NSDictionary<NSString *, id> *listsByID) {
  if (![storage respondsToSelector:NSSelectorFromString(@"listID")]) {
    return @[];
  }
  NSString *listIdentifier = [storage valueForKeyPath:@"listID.uuid.UUIDString"];
  id list = [listIdentifier isKindOfClass:NSString.class] ? listsByID[listIdentifier] : nil;
  if (![list respondsToSelector:NSSelectorFromString(@"sharees")]) {
    return @[];
  }
  id sharees = [list valueForKey:@"sharees"];
  return [sharees isKindOfClass:NSArray.class] ? sharees : @[];
}

static NSArray *_Nullable RPURLAttachmentsIn(id _Nullable attachments, Class _Nullable urlAttachmentClass) {
  if (urlAttachmentClass == Nil) {
    return nil;
  }
  if (attachments == nil) {
    return @[];
  }
  if (![attachments isKindOfClass:NSArray.class]) {
    return nil;
  }
  NSMutableArray *urlAttachments = [NSMutableArray array];
  for (id attachment in (NSArray *)attachments) {
    if (![attachment isKindOfClass:urlAttachmentClass]) {
      continue;
    }
    if (![[attachment valueForKey:@"url"] isKindOfClass:NSURL.class]) {
      return nil;
    }
    [urlAttachments addObject:attachment];
  }
  return urlAttachments;
}

static NSArray *_Nullable RPStoredURLAttachments(id _Nullable storage, Class _Nullable urlAttachmentClass) {
  if (![storage respondsToSelector:NSSelectorFromString(@"attachments")]) {
    return nil;
  }
  return RPURLAttachmentsIn([storage valueForKey:@"attachments"], urlAttachmentClass);
}

static NSString *RPClassName(NSDictionary<NSString *, NSString *> *names, const char *className) {
  NSString *name = @(className);
  return names[name] ?: name;
}

static NSString *RPLinkKey(NSURL *url) {
  NSURLComponents *parts = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
  parts.scheme = parts.scheme.lowercaseString;
  parts.percentEncodedHost = parts.percentEncodedHost.lowercaseString;
  return parts.string ?: url.absoluteString;
}

static NSString *_Nullable RPLoadReminderKit(void) {
  if (dlopen(RPFrameworkPath, RTLD_NOW) != NULL) {
    return nil;
  }
  const char *message = dlerror();
  return [NSString stringWithFormat:@"ReminderKit did not load (%s)", message ?: "unknown error"];
}

static RPReadResult *RPReadStore(
    NSDictionary<NSString *, NSString *> *names, id store, NSSet<NSString *> *ids, BOOL openOnly);

static RPReadResult *RPRead(NSSet<NSString *> *ids, BOOL openOnly) {
  NSString *loadFailure = RPLoadReminderKit();
  if (loadFailure != nil) {
    return RPUnavailable(loadFailure);
  }
  Class storeClass = NSClassFromString(@"REMStore");
  if (storeClass == Nil) {
    return RPUnavailable(@"ReminderKit has no REMStore");
  }
  return RPReadStore(@{}, [storeClass new], ids, openOnly);
}

static RPReadResult *RPReadStore(
    NSDictionary<NSString *, NSString *> *names, id store, NSSet<NSString *> *ids, BOOL openOnly) {
  Class urlAttachmentClass = NSClassFromString(RPClassName(names, "REMURLAttachment"));
  NSString *reason = nil;
  NSArray *lists = RPInvokeWithErrorOut(store, @"fetchListsForEventKitBridgingWithError:", NULL, 0, &reason);
  if (![lists isKindOfClass:NSArray.class]) {
    return RPUnavailable(reason ?: @"REMStore lists are not an array");
  }
  NSMutableArray *listIDs = [NSMutableArray arrayWithCapacity:lists.count];
  NSMutableDictionary<NSString *, id> *listsByID = [NSMutableDictionary dictionaryWithCapacity:lists.count];
  for (id list in lists) {
    id listID = [list valueForKey:@"objectID"];
    if (listID == nil) {
      return RPUnavailable(@"a ReminderKit list has no objectID");
    }
    [listIDs addObject:listID];
    NSString *listIdentifier = [listID valueForKeyPath:@"uuid.UUIDString"];
    if ([listIdentifier isKindOfClass:NSString.class]) {
      listsByID[listIdentifier] = list;
    }
  }

  NSArray *reminders = openOnly
      ? RPInvokeWithErrorOut(store, @"fetchIncompleteRemindersForEventKitBridgingWithDueDateFrom:to:withListIDs:error:",
            (__unsafe_unretained id[]){nil, nil, listIDs}, 3, &reason)
      : RPInvokeWithErrorOut(store, @"fetchRemindersForEventKitBridgingWithListIDs:error:",
            (__unsafe_unretained id[]){listIDs}, 1, &reason);
  if (![reminders isKindOfClass:NSArray.class]) {
    return RPUnavailable(reason ?: @"REMStore reminders are not an array");
  }

  NSMutableDictionary<NSString *, RPReminderFields *> *fields = [NSMutableDictionary dictionary];
  for (id reminder in reminders) {
    NSString *identifier = [reminder valueForKeyPath:@"objectID.uuid.UUIDString"];
    if (![identifier isKindOfClass:NSString.class] || ![ids containsObject:identifier]) {
      continue;
    }
    id storage = [reminder valueForKey:@"storage"];
    NSNumber *flagged = [storage valueForKey:@"flagged"];
    NSNumber *urgent = [storage valueForKey:@"isUrgentStateEnabledForCurrentUser"];
    if (![flagged isKindOfClass:NSNumber.class] || ![urgent isKindOfClass:NSNumber.class]) {
      return RPUnavailable(@"a ReminderKit reminder has no flagged or Urgent value");
    }
    if (![storage respondsToSelector:NSSelectorFromString(@"hashtags")]
        || ![storage respondsToSelector:NSSelectorFromString(@"dueDateDeltaAlertsData")]) {
      return RPUnavailable(@"a ReminderKit reminder has no hashtags or Early Reminder data");
    }
    id hashtags = [storage valueForKey:@"hashtags"];
    id alertsData = [storage valueForKey:@"dueDateDeltaAlertsData"];
    if ((hashtags != nil && ![hashtags isKindOfClass:NSSet.class])
        || (alertsData != nil && ![alertsData isKindOfClass:NSData.class])) {
      return RPUnavailable(@"a ReminderKit reminder has hashtags or Early Reminder data of an unexpected type");
    }
    if (![storage respondsToSelector:NSSelectorFromString(@"parentReminderID")]
        || ![storage respondsToSelector:NSSelectorFromString(@"assignments")]) {
      return RPUnavailable(@"a ReminderKit reminder has no parent or assignment data");
    }
    id parentObjectID = [storage valueForKey:@"parentReminderID"];
    NSString *parentID = parentObjectID == nil ? nil : [parentObjectID valueForKeyPath:@"uuid.UUIDString"];
    id assignmentSet = [storage valueForKey:@"assignments"];
    if ((parentObjectID != nil && ![parentID isKindOfClass:NSString.class])
        || (assignmentSet != nil && ![assignmentSet isKindOfClass:NSSet.class])) {
      return RPUnavailable(@"a ReminderKit reminder has a parent or assignment of an unexpected type");
    }
    NSMutableArray<NSString *> *tags = [NSMutableArray array];
    for (id hashtag in (NSSet *)hashtags) {
      id name = [hashtag valueForKey:@"name"];
      if (![name isKindOfClass:NSString.class]) {
        return RPUnavailable(@"a ReminderKit hashtag has no name");
      }
      [tags addObject:name];
    }
    NSArray *sharees = assignmentSet == nil ? @[] : RPShareesForReminder(storage, listsByID);
    NSMutableArray<RPAssignment *> *assignments = [NSMutableArray array];
    for (id assignment in (NSSet *)assignmentSet) {
      NSString *assigneeID = [assignment valueForKeyPath:@"assigneeID.uuid.UUIDString"];
      NSNumber *status = [assignment valueForKey:@"status"];
      id assignedDate = [assignment valueForKey:@"assignedDate"];
      if (![assigneeID isKindOfClass:NSString.class] || ![status isKindOfClass:NSNumber.class]
          || (assignedDate != nil && ![assignedDate isKindOfClass:NSDate.class])) {
        return RPUnavailable(@"a ReminderKit assignment has no assignee, status or date of the expected type");
      }
      id sharee = nil;
      for (id candidate in sharees) {
        if ([[candidate valueForKeyPath:@"objectID.uuid.UUIDString"] isEqual:assigneeID]) {
          sharee = candidate;
          break;
        }
      }
      [assignments addObject:[[RPAssignment alloc] initWithAssigneeID:assigneeID
                                                          displayName:RPOptionalString(sharee, @"displayName")
                                                            firstName:RPOptionalString(sharee, @"firstName")
                                                             lastName:RPOptionalString(sharee, @"lastName")
                                                               status:status.integerValue
                                                         assignedDate:assignedDate]];
    }
    NSArray<NSString *> *links =
        [RPStoredURLAttachments(storage, urlAttachmentClass) valueForKeyPath:@"url.absoluteString"];
    fields[identifier] = [[RPReminderFields alloc] initWithFlagged:flagged.boolValue
                                                            urgent:urgent.boolValue
                                                              tags:tags
                                            dueDateDeltaAlertsData:alertsData
                                                          parentID:parentID
                                                       assignments:assignments
                                                             links:links];
  }
  return [[RPReadResult alloc] initWithFields:fields unavailableReason:nil];
}

static id _Nullable RPRunWithTimeout(
    NSTimeInterval timeout, id _Nullable (^work)(void), id _Nullable (^failure)(NSString *reason, BOOL outcomeUnknown)) {
  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  __block id result = nil;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    @autoreleasepool {
      id answer;
      @try {
        answer = work();
      } @catch (NSException *exception) {
        answer = failure([NSString stringWithFormat:@"ReminderKit raised %@: %@", exception.name, exception.reason],
                         YES);
      }
      result = answer;
    }
    dispatch_semaphore_signal(done);
  });

  if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))) != 0) {
    return failure([NSString stringWithFormat:@"ReminderKit did not answer within %g seconds", timeout], YES);
  }
  return result;
}

RPReadResult *RPReadWithTimeout(NSTimeInterval timeout, RPReadResult *(^read)(void)) {
  return RPRunWithTimeout(
      timeout, ^id { return read(); }, ^id(NSString *reason, BOOL outcomeUnknown) { return RPUnavailable(reason); });
}

RPReadResult *RPReadReminderFields(NSSet<NSString *> *ids, BOOL openOnly, NSTimeInterval timeout) {
  return RPReadWithTimeout(timeout, ^{
    return RPRead(ids, openOnly);
  });
}

RPReadResult *RPReadStoreForTesting(
    id store, NSSet<NSString *> *ids, BOOL openOnly, NSDictionary<NSString *, NSString *> *classNames) {
  return RPReadStore(classNames, store, ids, openOnly);
}

id _Nullable RPInvokeForTesting(
    id target, NSString *selectorName, NSArray *arguments, NSString *_Nullable *_Nonnull reason) {
  NSUInteger count = arguments.count;
  __unsafe_unretained id buffer[count + 1];
  [arguments getObjects:buffer range:NSMakeRange(0, count)];
  NSString *failure = nil;
  id result = RPInvokeWithErrorOut(target, selectorName, buffer, count, &failure);
  *reason = failure;
  return result;
}

@protocol RPReminderKitWriting <NSObject>
+ (nullable id)objectIDWithURL:(NSURL *)url;
- (nullable id)fetchReminderWithObjectID:(id)objectID error:(NSError **)error;
- (nullable id)initWithStore:(id)store;
- (nullable id)updateReminder:(id)reminder;
- (nullable id)flaggedContext;
- (void)setFlagged:(NSInteger)flagged;
- (nullable id)urgentAlarmContext;
- (void)setIsUrgentStateEnabledForCurrentUser:(BOOL)enabled;
- (nullable id)dueDateDeltaAlertContext;
- (void)removeAllFetchedDueDateDeltaAlerts;
- (void)removeDueDateDeltaAlertsWithIdentifiers:(NSArray<NSUUID *> *)identifiers;
- (nullable id)addDueDateDeltaAlertWithDueDateDelta:(id)dueDateDelta;
- (nullable id)initWithUnit:(NSInteger)unit count:(NSInteger)count;
- (nullable id)hashtagContext;
- (nullable id)hashtags;
- (nullable id)addHashtagWithType:(NSInteger)type name:(NSString *)name;
- (void)removeHashtag:(id)hashtag;
- (nullable id)attachmentContext;
- (nullable id)urlAttachments;
- (nullable id)addURLAttachmentWithURL:(NSURL *)url;
- (void)removeAttachment:(id)attachment;
- (BOOL)saveSynchronouslyWithError:(NSError **)error;
@end

typedef NS_ENUM(NSInteger, RPWriteNeed) {
  RPNeededAlways,
  RPNeededForFlag,
  RPNeededForUrgent,
  RPNeededForEarlyReminder,
  RPNeededForEarlyReminderSet,
  RPNeededForTags,
  RPNeededForTagAdd,
  RPNeededForTagRemoval,
  RPNeededForLinks,
  RPNeededForLinkAdd,
  RPNeededForLinkRemoval,
};

typedef struct {
  const char *className;
  const char *selector;
  BOOL classMethod;
  const char *types;
  RPWriteNeed need;
} RPRequirement;

static const RPRequirement RPReadRequirements[] = {
    {"REMStore", "fetchListsForEventKitBridgingWithError:", NO, "@@:^@", RPNeededAlways},
    {"REMStore", "fetchRemindersForEventKitBridgingWithListIDs:error:", NO, "@@:@^@", RPNeededAlways},
    {"REMListStorage", "objectID", NO, "@@:", RPNeededAlways},
    {"REMObjectID", "uuid", NO, "@@:", RPNeededAlways},
    {"REMReminder", "storage", NO, "@@:", RPNeededAlways},
    {"REMReminderStorage", "objectID", NO, "@@:", RPNeededAlways},
    {"REMReminderStorage", "flagged", NO, "q@:", RPNeededAlways},
    {"REMReminderStorage", "isUrgentStateEnabledForCurrentUser", NO, "B@:", RPNeededAlways},
    {"REMReminderStorage", "hashtags", NO, "@@:", RPNeededAlways},
    {"REMReminderStorage", "dueDateDeltaAlertsData", NO, "@@:", RPNeededAlways},
    {"REMReminderStorage", "parentReminderID", NO, "@@:", RPNeededAlways},
    {"REMReminderStorage", "assignments", NO, "@@:", RPNeededAlways},
    {"REMHashtag", "name", NO, "@@:", RPNeededAlways},
    {"REMAssignment", "assigneeID", NO, "@@:", RPNeededAlways},
    {"REMAssignment", "status", NO, "q@:", RPNeededAlways},
    {"REMAssignment", "assignedDate", NO, "@@:", RPNeededAlways},
};

static const RPRequirement RPWriteRequirements[] = {
    {"REMObjectID", "objectIDWithURL:", YES, "@@:@", RPNeededAlways},
    {"REMStore", "fetchReminderWithObjectID:error:", NO, "@@:@^@", RPNeededAlways},
    {"REMSaveRequest", "initWithStore:", NO, "@@:@", RPNeededAlways},
    {"REMSaveRequest", "updateReminder:", NO, "@@:@", RPNeededAlways},
    {"REMSaveRequest", "saveSynchronouslyWithError:", NO, "B@:^@", RPNeededAlways},
    {"REMReminderChangeItem", "flaggedContext", NO, "@@:", RPNeededForFlag},
    {"REMReminderFlaggedContextChangeItem", "setFlagged:", NO, "v@:q", RPNeededForFlag},
    {"REMReminderChangeItem", "urgentAlarmContext", NO, "@@:", RPNeededForUrgent},
    {"REMReminderUrgentAlarmContextChangeItem", "setIsUrgentStateEnabledForCurrentUser:", NO, "v@:B",
     RPNeededForUrgent},
    {"REMReminder", "storage", NO, "@@:", RPNeededForEarlyReminder},
    {"REMReminderStorage", "dueDateDeltaAlertsData", NO, "@@:", RPNeededForEarlyReminder},
    {"REMReminderChangeItem", "dueDateDeltaAlertContext", NO, "@@:", RPNeededForEarlyReminder},
    {"REMReminderDueDateDeltaAlertContextChangeItem", "removeAllFetchedDueDateDeltaAlerts", NO, "v@:",
     RPNeededForEarlyReminder},
    {"REMReminderDueDateDeltaAlertContextChangeItem", "addDueDateDeltaAlertWithDueDateDelta:", NO, "@@:@",
     RPNeededForEarlyReminder},
    {"REMReminderDueDateDeltaAlertContextChangeItem", "removeDueDateDeltaAlertsWithIdentifiers:", NO, "v@:@",
     RPNeededForEarlyReminder},
    {"REMDueDateDeltaInterval", "initWithUnit:count:", NO, "@@:qq", RPNeededForEarlyReminderSet},
    {"REMReminder", "storage", NO, "@@:", RPNeededForTags},
    {"REMReminderStorage", "hashtags", NO, "@@:", RPNeededForTags},
    {"REMHashtag", "name", NO, "@@:", RPNeededForTags},
    {"REMReminderChangeItem", "hashtagContext", NO, "@@:", RPNeededForTags},
    {"REMReminderHashtagContextChangeItem", "hashtags", NO, "@@:", RPNeededForTags},
    {"REMReminderHashtagContextChangeItem", "addHashtagWithType:name:", NO, "@@:q@", RPNeededForTagAdd},
    {"REMReminderHashtagContextChangeItem", "removeHashtag:", NO, "v@:@", RPNeededForTagRemoval},
    {"REMReminder", "storage", NO, "@@:", RPNeededForLinks},
    {"REMReminderStorage", "attachments", NO, "@@:", RPNeededForLinks},
    {"REMURLAttachment", "url", NO, "@@:", RPNeededForLinks},
    {"REMReminderChangeItem", "attachmentContext", NO, "@@:", RPNeededForLinks},
    {"REMReminderAttachmentContextChangeItem", "urlAttachments", NO, "@@:", RPNeededForLinks},
    {"REMReminderAttachmentContextChangeItem", "addURLAttachmentWithURL:", NO, "@@:@", RPNeededForLinkAdd},
    {"REMReminderAttachmentContextChangeItem", "removeAttachment:", NO, "v@:@", RPNeededForLinkRemoval},
};

static BOOL RPChangeNeeds(RPReminderChange *change, RPWriteNeed need) {
  switch (need) {
    case RPNeededAlways:
      return YES;
    case RPNeededForFlag:
      return change.flagged != nil;
    case RPNeededForUrgent:
      return change.urgent != nil;
    case RPNeededForEarlyReminder:
      return change.earlyReminder != nil;
    case RPNeededForEarlyReminderSet:
      return change.earlyReminder != nil && !change.earlyReminder.removes;
    case RPNeededForTags:
      return change.tagsToAdd.count > 0 || change.tagsToRemove.count > 0;
    case RPNeededForTagAdd:
      return change.tagsToAdd.count > 0;
    case RPNeededForTagRemoval:
      return change.tagsToRemove.count > 0;
    case RPNeededForLinks:
      return change.linksToAdd.count > 0 || change.linksToRemove.count > 0;
    case RPNeededForLinkAdd:
      return change.linksToAdd.count > 0;
    case RPNeededForLinkRemoval:
      return change.linksToRemove.count > 0;
  }
}

static NSString *RPTypesWithoutOffsets(Method method) {
  NSString *encoding = @(method_getTypeEncoding(method));
  NSCharacterSet *digits = NSCharacterSet.decimalDigitCharacterSet;
  return [[encoding componentsSeparatedByCharactersInSet:digits] componentsJoinedByString:@""];
}

static NSString *_Nullable RPCheckClasses(
    NSDictionary<NSString *, NSString *> *names, const RPRequirement *requirements, size_t count,
    RPReminderChange *_Nullable change) {
  for (size_t index = 0; index < count; index++) {
    RPRequirement requirement = requirements[index];
    if (change != nil && requirement.need != RPNeededAlways && !RPChangeNeeds(change, requirement.need)) {
      continue;
    }
    NSString *className = RPClassName(names, requirement.className);
    Class owner = NSClassFromString(className);
    if (owner == Nil) {
      return [NSString stringWithFormat:@"ReminderKit has no %@", className];
    }
    SEL selector = sel_registerName(requirement.selector);
    Method method = requirement.classMethod ? class_getClassMethod(owner, selector)
                                            : class_getInstanceMethod(owner, selector);
    if (method == NULL) {
      return [NSString stringWithFormat:@"%@ has no %s", className, requirement.selector];
    }
    if (![RPTypesWithoutOffsets(method) isEqualToString:@(requirement.types)]) {
      return [NSString stringWithFormat:@"%@ %s has an unexpected signature", className, requirement.selector];
    }
  }
  return nil;
}

static NSString *_Nullable RPCheckWriteClasses(
    NSDictionary<NSString *, NSString *> *names, RPReminderChange *_Nullable change) {
  size_t count = sizeof(RPWriteRequirements) / sizeof(RPWriteRequirements[0]);
  return RPCheckClasses(names, RPWriteRequirements, count, change);
}

static NSString *_Nullable RPCheckReadClasses(NSDictionary<NSString *, NSString *> *names) {
  size_t count = sizeof(RPReadRequirements) / sizeof(RPReadRequirements[0]);
  return RPCheckClasses(names, RPReadRequirements, count, nil);
}

static NSArray<NSUUID *> *_Nullable RPDueDateDeltaAlertIDs(id reminder) {
  id storage = [reminder respondsToSelector:NSSelectorFromString(@"storage")] ? [reminder valueForKey:@"storage"] : nil;
  if (![storage respondsToSelector:NSSelectorFromString(@"dueDateDeltaAlertsData")]) {
    return nil;
  }
  id data = [storage valueForKey:@"dueDateDeltaAlertsData"];
  if (data == nil) {
    return @[];
  }
  id stored =
      [data isKindOfClass:NSData.class] ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
  id alerts = [stored isKindOfClass:NSDictionary.class] ? stored[@"dueDateDeltaAlerts"] : nil;
  if (![alerts isKindOfClass:NSArray.class]) {
    return nil;
  }
  NSMutableArray<NSUUID *> *ids = [NSMutableArray array];
  for (id alert in (NSArray *)alerts) {
    id identifier = [alert isKindOfClass:NSDictionary.class] ? alert[@"identifier"] : nil;
    NSUUID *uuid = [identifier isKindOfClass:NSString.class] ? [[NSUUID alloc] initWithUUIDString:identifier] : nil;
    if (uuid == nil) {
      return nil;
    }
    [ids addObject:uuid];
  }
  return ids;
}

static NSArray *_Nullable RPHashtagsIn(id _Nullable hashtags) {
  if (hashtags == nil) {
    return @[];
  }
  if (![hashtags isKindOfClass:NSSet.class]) {
    return nil;
  }
  for (id hashtag in (NSSet *)hashtags) {
    if (![[hashtag valueForKey:@"name"] isKindOfClass:NSString.class]) {
      return nil;
    }
  }
  return ((NSSet *)hashtags).allObjects;
}

static NSArray *_Nullable RPStoredHashtags(id reminder) {
  id storage = [reminder respondsToSelector:NSSelectorFromString(@"storage")] ? [reminder valueForKey:@"storage"] : nil;
  if (![storage respondsToSelector:NSSelectorFromString(@"hashtags")]) {
    return nil;
  }
  return RPHashtagsIn([storage valueForKey:@"hashtags"]);
}

static NSArray *RPHashtagsNamed(NSArray *hashtags, NSString *name) {
  return [hashtags filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id hashtag, NSDictionary *_) {
                     return [[hashtag valueForKey:@"name"] caseInsensitiveCompare:name] == NSOrderedSame;
                   }]];
}

static NSArray *RPAttachmentsLinking(NSArray *attachments, NSURL *url) {
  NSString *key = RPLinkKey(url);
  return [attachments filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id attachment, NSDictionary *_) {
                        return [RPLinkKey([attachment valueForKey:@"url"]) isEqualToString:key];
                      }]];
}

static NSString *_Nullable RPWrite(
    NSDictionary<NSString *, NSString *> *names, NSString *reminderID, RPReminderChange *change) {
  NSString *missing = RPCheckWriteClasses(names, change);
  if (missing != nil) {
    return missing;
  }
  if ([[NSUUID alloc] initWithUUIDString:reminderID] == nil) {
    return [NSString stringWithFormat:@"%@ is not a ReminderKit id", reminderID];
  }

  NSURL *url = [NSURL URLWithString:[@"x-apple-reminderkit://REMCDReminder/" stringByAppendingString:reminderID]];
  Class<RPReminderKitWriting> objectIDClass = NSClassFromString(RPClassName(names, "REMObjectID"));
  id objectID = [objectIDClass objectIDWithURL:url];
  if (objectID == nil) {
    return @"REMObjectID objectIDWithURL: returned nothing";
  }

  id<RPReminderKitWriting> store = [NSClassFromString(RPClassName(names, "REMStore")) new];
  NSError *error = nil;
  id reminder = [store fetchReminderWithObjectID:objectID error:&error];
  if (error != nil) {
    return error.localizedDescription;
  }
  if (reminder == nil) {
    return [NSString stringWithFormat:@"ReminderKit found no reminder with id %@", reminderID];
  }
  NSArray<NSUUID *> *existingAlertIDs = change.earlyReminder == nil ? @[] : RPDueDateDeltaAlertIDs(reminder);
  if (existingAlertIDs == nil) {
    return @"the Early Reminders already on the reminder could not be read";
  }
  BOOL changesTags = change.tagsToAdd.count > 0 || change.tagsToRemove.count > 0;
  NSArray *storedHashtags = changesTags ? RPStoredHashtags(reminder) : @[];
  if (storedHashtags == nil) {
    return @"the tags already on the reminder could not be read";
  }
  BOOL changesLinks = change.linksToAdd.count > 0 || change.linksToRemove.count > 0;
  id storage = changesLinks && [reminder respondsToSelector:NSSelectorFromString(@"storage")]
      ? [reminder valueForKey:@"storage"]
      : nil;
  Class urlAttachmentClass = NSClassFromString(RPClassName(names, "REMURLAttachment"));
  NSArray *storedLinks = changesLinks ? RPStoredURLAttachments(storage, urlAttachmentClass) : @[];
  if (storedLinks == nil) {
    return @"the links already on the reminder could not be read";
  }

  id<RPReminderKitWriting> save =
      [(id<RPReminderKitWriting>)[NSClassFromString(RPClassName(names, "REMSaveRequest")) alloc] initWithStore:store];
  id<RPReminderKitWriting> reminderChange = [save updateReminder:reminder];
  if (reminderChange == nil
      || (change.flagged != nil && ![reminderChange respondsToSelector:@selector(flaggedContext)])
      || (change.urgent != nil && ![reminderChange respondsToSelector:@selector(urgentAlarmContext)])
      || (change.earlyReminder != nil && ![reminderChange respondsToSelector:@selector(dueDateDeltaAlertContext)])
      || (changesTags && ![reminderChange respondsToSelector:@selector(hashtagContext)])
      || (changesLinks && ![reminderChange respondsToSelector:@selector(attachmentContext)])) {
    return @"REMSaveRequest updateReminder: returned no reminder change";
  }
  id<RPReminderKitWriting> hashtagContext = changesTags ? [reminderChange hashtagContext] : nil;
  NSMutableArray *hashtags = [storedHashtags mutableCopy];
  if (changesTags) {
    if (![hashtagContext respondsToSelector:@selector(hashtags)]
        || (change.tagsToAdd.count > 0 && ![hashtagContext respondsToSelector:@selector(addHashtagWithType:name:)])
        || (change.tagsToRemove.count > 0 && ![hashtagContext respondsToSelector:@selector(removeHashtag:)])) {
      return @"REMReminderChangeItem hashtagContext returned no tag change";
    }
    NSArray *contextHashtags = RPHashtagsIn([hashtagContext hashtags]);
    if (contextHashtags == nil) {
      return @"the tags already on the reminder could not be read";
    }
    for (id hashtag in contextHashtags) {
      if (![hashtags containsObject:hashtag]) {
        [hashtags addObject:hashtag];
      }
    }
  }
  id<RPReminderKitWriting> attachmentContext = changesLinks ? [reminderChange attachmentContext] : nil;
  NSMutableArray *urlAttachments = [storedLinks mutableCopy];
  if (changesLinks) {
    if (![attachmentContext respondsToSelector:@selector(urlAttachments)]
        || (change.linksToAdd.count > 0 && ![attachmentContext respondsToSelector:@selector(addURLAttachmentWithURL:)])
        || (change.linksToRemove.count > 0 && ![attachmentContext respondsToSelector:@selector(removeAttachment:)])) {
      return @"REMReminderChangeItem attachmentContext returned no link change";
    }
    NSArray *contextAttachments = RPURLAttachmentsIn([attachmentContext urlAttachments], urlAttachmentClass);
    if (contextAttachments == nil) {
      return @"the links already on the reminder could not be read";
    }
    for (id attachment in contextAttachments) {
      if (![urlAttachments containsObject:attachment]) {
        [urlAttachments addObject:attachment];
      }
    }
  }
  if (change.flagged != nil) {
    id<RPReminderKitWriting> flaggedContext = [reminderChange flaggedContext];
    if (![flaggedContext respondsToSelector:@selector(setFlagged:)]) {
      return @"REMReminderChangeItem flaggedContext returned no flag change";
    }
    [flaggedContext setFlagged:change.flagged.boolValue ? 1 : 0];
  }
  if (change.urgent != nil) {
    id<RPReminderKitWriting> urgentContext = [reminderChange urgentAlarmContext];
    if (![urgentContext respondsToSelector:@selector(setIsUrgentStateEnabledForCurrentUser:)]) {
      return @"REMReminderChangeItem urgentAlarmContext returned no Urgent change";
    }
    [urgentContext setIsUrgentStateEnabledForCurrentUser:change.urgent.boolValue];
  }
  RPEarlyReminderChange *early = change.earlyReminder;
  if (early != nil) {
    id<RPReminderKitWriting> alertContext = [reminderChange dueDateDeltaAlertContext];
    if (![alertContext respondsToSelector:@selector(removeAllFetchedDueDateDeltaAlerts)]
        || ![alertContext respondsToSelector:@selector(addDueDateDeltaAlertWithDueDateDelta:)]
        || ![alertContext respondsToSelector:@selector(removeDueDateDeltaAlertsWithIdentifiers:)]) {
      return @"REMReminderChangeItem dueDateDeltaAlertContext returned no Early Reminder change";
    }
    if (existingAlertIDs.count > 0) {
      [alertContext removeDueDateDeltaAlertsWithIdentifiers:existingAlertIDs];
    }
    [alertContext removeAllFetchedDueDateDeltaAlerts];
    if (!early.removes) {
      id delta = [(id<RPReminderKitWriting>)[NSClassFromString(RPClassName(names, "REMDueDateDeltaInterval")) alloc]
          initWithUnit:early.unit
                 count:early.count];
      if (delta == nil) {
        return @"REMDueDateDeltaInterval initWithUnit:count: returned nothing";
      }
      if ([alertContext addDueDateDeltaAlertWithDueDateDelta:delta] == nil) {
        return @"REMReminderDueDateDeltaAlertContextChangeItem addDueDateDeltaAlertWithDueDateDelta: returned no alert";
      }
    }
  }

  for (NSString *name in change.tagsToRemove) {
    for (id hashtag in RPHashtagsNamed(hashtags, name)) {
      [hashtagContext removeHashtag:hashtag];
    }
  }
  for (NSString *name in change.tagsToAdd) {
    if (RPHashtagsNamed(hashtags, name).count > 0) {
      continue;
    }
    if ([hashtagContext addHashtagWithType:1 name:name] == nil) {
      return @"REMReminderHashtagContextChangeItem addHashtagWithType:name: returned no tag";
    }
  }
  for (NSURL *url in change.linksToRemove) {
    for (id attachment in RPAttachmentsLinking(urlAttachments, url)) {
      [attachmentContext removeAttachment:attachment];
    }
  }
  for (NSURL *url in change.linksToAdd) {
    if (RPAttachmentsLinking(urlAttachments, url).count > 0) {
      continue;
    }
    if ([attachmentContext addURLAttachmentWithURL:url] == nil) {
      return @"REMReminderAttachmentContextChangeItem addURLAttachmentWithURL: returned no link";
    }
  }

  error = nil;
  BOOL saved = [save saveSynchronouslyWithError:&error];
  if (error != nil) {
    return error.localizedDescription;
  }
  return saved ? nil : @"REMSaveRequest did not save";
}

NSString *_Nullable RPWriteUnavailableReason(RPReminderChange *change) {
  return RPLoadReminderKit() ?: RPCheckWriteClasses(@{}, change);
}

NSString *_Nullable RPWriteTableUnavailableReason(void) {
  return RPLoadReminderKit() ?: RPCheckWriteClasses(@{}, nil);
}

NSString *_Nullable RPWriteTableUnavailableReasonWithClassesForTesting(NSDictionary<NSString *, NSString *> *classNames) {
  return RPCheckWriteClasses(classNames, nil);
}

NSString *_Nullable RPReadUnavailableReason(void) {
  return RPLoadReminderKit() ?: RPCheckReadClasses(@{});
}

NSString *_Nullable RPReadUnavailableReasonWithClassesForTesting(NSDictionary<NSString *, NSString *> *classNames) {
  return RPCheckReadClasses(classNames);
}

static RPWriteResult *RPWriteWithTimeout(NSTimeInterval timeout, NSString *_Nullable (^write)(void)) {
  return RPRunWithTimeout(
      timeout, ^id { return [[RPWriteResult alloc] initWithFailureReason:write() outcomeUnknown:NO]; },
      ^id(NSString *reason, BOOL outcomeUnknown) {
        return [[RPWriteResult alloc] initWithFailureReason:reason outcomeUnknown:outcomeUnknown];
      });
}

RPWriteResult *RPWriteReminderFields(NSString *reminderID, RPReminderChange *change, NSTimeInterval timeout) {
  return RPWriteWithTimeout(timeout, ^NSString * { return RPLoadReminderKit() ?: RPWrite(@{}, reminderID, change); });
}

RPWriteResult *RPWriteWithClassesForTesting(
    NSDictionary<NSString *, NSString *> *classNames, NSString *reminderID, RPReminderChange *change,
    NSTimeInterval timeout) {
  return RPWriteWithTimeout(timeout, ^NSString * { return RPWrite(classNames, reminderID, change); });
}
