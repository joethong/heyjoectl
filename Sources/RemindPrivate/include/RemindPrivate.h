#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RPAssignment : NSObject
@property(nonatomic, readonly) NSString *assigneeID;
@property(nonatomic, readonly, nullable) NSString *displayName;
@property(nonatomic, readonly, nullable) NSString *firstName;
@property(nonatomic, readonly, nullable) NSString *lastName;
@property(nonatomic, readonly) NSInteger status;
@property(nonatomic, readonly, nullable) NSDate *assignedDate;
@end

@interface RPReminderFields : NSObject
@property(nonatomic, readonly) BOOL flagged;
@property(nonatomic, readonly) BOOL urgent;
@property(nonatomic, readonly) NSArray<NSString *> *tags;
@property(nonatomic, readonly, nullable) NSData *dueDateDeltaAlertsData;
@property(nonatomic, readonly, nullable) NSString *parentID;
@property(nonatomic, readonly) NSArray<RPAssignment *> *assignments;
@property(nonatomic, readonly, nullable) NSArray<NSString *> *links;
@end

@interface RPReadResult : NSObject
@property(nonatomic, readonly) NSDictionary<NSString *, RPReminderFields *> *fields;
@property(nonatomic, readonly, nullable) NSString *unavailableReason;
- (instancetype)initWithFields:(NSDictionary<NSString *, RPReminderFields *> *)fields
             unavailableReason:(nullable NSString *)unavailableReason;
@end

@interface RPEarlyReminderChange : NSObject
@property(nonatomic, readonly) BOOL removes;
@property(nonatomic, readonly) NSInteger unit;
@property(nonatomic, readonly) NSInteger count;
+ (instancetype)removal;
- (instancetype)initWithUnit:(NSInteger)unit count:(NSInteger)count;
@end

@interface RPReminderChange : NSObject
@property(nonatomic, readonly, nullable) NSNumber *flagged;
@property(nonatomic, readonly, nullable) NSNumber *urgent;
@property(nonatomic, readonly, nullable) RPEarlyReminderChange *earlyReminder;
@property(nonatomic, readonly) NSArray<NSString *> *tagsToAdd;
@property(nonatomic, readonly) NSArray<NSString *> *tagsToRemove;
@property(nonatomic, readonly) NSArray<NSURL *> *linksToAdd;
@property(nonatomic, readonly) NSArray<NSURL *> *linksToRemove;
- (instancetype)initWithFlagged:(nullable NSNumber *)flagged urgent:(nullable NSNumber *)urgent;
- (instancetype)initWithFlagged:(nullable NSNumber *)flagged
                         urgent:(nullable NSNumber *)urgent
                  earlyReminder:(nullable RPEarlyReminderChange *)earlyReminder;
- (instancetype)initWithFlagged:(nullable NSNumber *)flagged
                         urgent:(nullable NSNumber *)urgent
                  earlyReminder:(nullable RPEarlyReminderChange *)earlyReminder
                      tagsToAdd:(NSArray<NSString *> *)tagsToAdd
                   tagsToRemove:(NSArray<NSString *> *)tagsToRemove;
- (instancetype)initWithFlagged:(nullable NSNumber *)flagged
                         urgent:(nullable NSNumber *)urgent
                  earlyReminder:(nullable RPEarlyReminderChange *)earlyReminder
                      tagsToAdd:(NSArray<NSString *> *)tagsToAdd
                   tagsToRemove:(NSArray<NSString *> *)tagsToRemove
                     linksToAdd:(NSArray<NSURL *> *)linksToAdd
                  linksToRemove:(NSArray<NSURL *> *)linksToRemove;
@end

@interface RPWriteResult : NSObject
@property(nonatomic, readonly, nullable) NSString *failureReason;
/// YES when the write timed out or raised, so it may still have saved.
@property(nonatomic, readonly) BOOL outcomeUnknown;
@end

/// Reads ReminderKit fields for the reminders whose EventKit ids are in `ids`.
/// Never throws: any missing class or selector, error, exception or time-out
/// comes back as `unavailableReason`.
RPReadResult *RPReadReminderFields(NSSet<NSString *> *ids, BOOL openOnly, NSTimeInterval timeout);

/// Test seam for `RPReadReminderFields` without loading ReminderKit: reads from `store`, a stand-in REMStore.
/// `classNames` maps each ReminderKit class name to a stand-in class name.
RPReadResult *RPReadStoreForTesting(
    id store, NSSet<NSString *> *ids, BOOL openOnly, NSDictionary<NSString *, NSString *> *classNames);

/// Runs `read` on a background queue and waits at most `timeout` seconds. A time-out or a raised
/// exception comes back as `unavailableReason`. `RPReadReminderFields` goes through this.
RPReadResult *RPReadWithTimeout(NSTimeInterval timeout, RPReadResult *(^read)(void));

/// Test seam for the selector and signature checks `RPReadReminderFields` makes on REMStore. Calls
/// `selectorName` on `target` with `arguments` plus an error out-parameter. Returns the result, or nil
/// with `reason` set.
id _Nullable RPInvokeForTesting(
    id target, NSString *selectorName, NSArray *arguments, NSString *_Nullable *_Nonnull reason);

/// Returns nil when ReminderKit has every class and method writing `change` needs, with the expected types; otherwise
/// the reason. Calls nothing in ReminderKit.
NSString *_Nullable RPWriteUnavailableReason(RPReminderChange *change);

/// Returns nil when ReminderKit has every class and method any write needs, with the expected types; otherwise the
/// reason. Checks the whole write table, whatever a change would use. Calls nothing in ReminderKit and fetches and saves
/// nothing.
NSString *_Nullable RPWriteTableUnavailableReason(void);

/// Test seam for `RPWriteTableUnavailableReason` without loading ReminderKit: `classNames` maps each ReminderKit class
/// name to a stand-in class name.
NSString *_Nullable RPWriteTableUnavailableReasonWithClassesForTesting(NSDictionary<NSString *, NSString *> *classNames);

/// Returns nil when ReminderKit has every class and method a full-scope `RPReadReminderFields` needs, with the
/// expected types; otherwise the reason. Calls nothing in ReminderKit.
NSString *_Nullable RPReadUnavailableReason(void);

/// Test seam for `RPReadUnavailableReason` without loading ReminderKit: `classNames` maps each ReminderKit class name
/// to a stand-in class name.
NSString *_Nullable RPReadUnavailableReasonWithClassesForTesting(NSDictionary<NSString *, NSString *> *classNames);

/// Saves `change` to the reminder whose EventKit id is `reminderID`, in one ReminderKit save. Never throws: a missing
/// class or method, an error, an exception or a time-out comes back as `failureReason`.
RPWriteResult *RPWriteReminderFields(NSString *reminderID, RPReminderChange *change, NSTimeInterval timeout);

/// Test seam for `RPWriteReminderFields` without loading ReminderKit: `classNames` maps each ReminderKit class name to
/// a stand-in class name.
RPWriteResult *RPWriteWithClassesForTesting(
    NSDictionary<NSString *, NSString *> *classNames, NSString *reminderID, RPReminderChange *change,
    NSTimeInterval timeout);

NS_ASSUME_NONNULL_END
