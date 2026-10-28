// The Investigate card words and alerts, issue #35, for each expert that offers it on its cards.
// They work on plain values and use no Core class, so the render tool and the kit's checks link them alone.
// An expert puts each finding's last run in its view as -[MMInvestigation json], read from memory, adds
// "Investigate…" with the tail and reason below, and routes the action to
// -[MMInvestigations ask:snapshot:confirm:failed:] with the two alerts. AppKit, main thread.
#import <Foundation/Foundation.h>

/// The gray tail of "Investigate…": the last answer's age, or nil. run is -[MMInvestigation json] or nil.
NSString *MMInvestigateTail(NSDictionary *run);
/// "running now" while a run goes, so the action is dimmed, else nil.
NSString *MMInvestigateDisabledReason(NSDictionary *run);
/// The card's note for run: "Haiku investigated", then the whole sentences of the answer that fit in the note's
/// two lines. While a run goes, or after it failed, it says so. NO when run is nil, and the card keeps its note.
BOOL MMInvestigateNote(NSDictionary *run, NSString **noteBy, NSString **note);
/// The alert that shows the cost and the model, with a field for the question.
/// Returns the question, empty for the default one, or nil when the person cancels.
NSString *MMInvestigateConfirm(NSString *title, NSString *text, NSString *placeholder);
/// The alert for a run that failed or could not start.
void MMInvestigateFailed(NSString *error);
