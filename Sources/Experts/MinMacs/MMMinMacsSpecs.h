// Makers for the specs of Core/MMExpert.h, used by the MinMacs expert. MMMinMacsSpecs.m says why they exist.
#import <Foundation/Foundation.h>
#import "Core/MMExpert.h"

MMActionSpec *MMMinMacsAction(NSString *title, NSString *tail, NSString *disabledReason, void (^run)(BOOL option));
/// At most three facts, empty ones left out.
MMRowSpec *MMMinMacsRow(NSString *name, NSArray<NSString *> *facts, MMRowMark mark, NSString *findingID);
MMSectionSpec *MMMinMacsSection(NSString *title, NSArray<MMRowSpec *> *rows);
MMMenuSpec *MMMinMacsMenu(void);
MMCardFact *MMMinMacsFact(NSString *label, NSString *value);
MMCardSpec *MMMinMacsCard(void);
MMVerbSpec *MMMinMacsVerb(NSString *verb, NSString *usage, BOOL mutates, int (^run)(MMArgs *args));
/// The words after the verb, such as @[@"quit", @"com.spotify.client", @"--force"].
NSArray<NSString *> *MMMinMacsWords(MMArgs *args, NSString *verb);
