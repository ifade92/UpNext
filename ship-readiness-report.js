const fs = require("fs");
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  Header, Footer, AlignmentType, HeadingLevel, BorderStyle, WidthType,
  ShadingType, PageNumber, PageBreak, LevelFormat
} = require("docx");

// Color palette
const ACCENT = "2ECC71";
const DARK = "0D2B1A";
const RED = "E74C3C";
const ORANGE = "F39C12";
const GRAY = "95A5A6";
const LIGHT_BG = "F8F9FA";
const WHITE = "FFFFFF";

const border = { style: BorderStyle.SINGLE, size: 1, color: "CCCCCC" };
const borders = { top: border, bottom: border, left: border, right: border };
const cellMargins = { top: 80, bottom: 80, left: 120, right: 120 };

function heading(text, level = HeadingLevel.HEADING_1) {
  return new Paragraph({ heading: level, children: [new TextRun({ text, bold: true })] });
}

function para(text, opts = {}) {
  return new Paragraph({
    spacing: { after: 120 },
    ...opts,
    children: [new TextRun({ text, size: 22, ...opts.run })]
  });
}

function boldPara(boldText, normalText) {
  return new Paragraph({
    spacing: { after: 120 },
    children: [
      new TextRun({ text: boldText, bold: true, size: 22 }),
      new TextRun({ text: normalText, size: 22 })
    ]
  });
}

function statusBadge(status) {
  const colors = { "CRITICAL": RED, "WARNING": ORANGE, "OK": ACCENT, "INFO": "3498DB" };
  return new TextRun({ text: ` [${status}] `, bold: true, color: colors[status] || GRAY, size: 22 });
}

function severityRow(severity, title, description, fix) {
  return new TableRow({
    children: [
      new TableCell({
        borders, width: { size: 1200, type: WidthType.DXA }, margins: cellMargins,
        shading: { fill: severity === "CRITICAL" ? "FDEDEC" : severity === "WARNING" ? "FEF9E7" : "EAFAF1", type: ShadingType.CLEAR },
        verticalAlign: "center",
        children: [new Paragraph({ alignment: AlignmentType.CENTER, children: [
          new TextRun({ text: severity, bold: true, size: 20, color: severity === "CRITICAL" ? RED : severity === "WARNING" ? ORANGE : ACCENT })
        ]})]
      }),
      new TableCell({
        borders, width: { size: 2400, type: WidthType.DXA }, margins: cellMargins,
        children: [new Paragraph({ children: [new TextRun({ text: title, bold: true, size: 20 })] })]
      }),
      new TableCell({
        borders, width: { size: 3360, type: WidthType.DXA }, margins: cellMargins,
        children: [new Paragraph({ children: [new TextRun({ text: description, size: 20 })] })]
      }),
      new TableCell({
        borders, width: { size: 2400, type: WidthType.DXA }, margins: cellMargins,
        children: [new Paragraph({ children: [new TextRun({ text: fix, size: 20 })] })]
      }),
    ]
  });
}

function headerRow(cols, widths) {
  return new TableRow({
    children: cols.map((col, i) => new TableCell({
      borders,
      width: { size: widths[i], type: WidthType.DXA },
      margins: cellMargins,
      shading: { fill: DARK, type: ShadingType.CLEAR },
      children: [new Paragraph({ children: [new TextRun({ text: col, bold: true, size: 20, color: WHITE })] })]
    }))
  });
}

function simpleRow(cols, widths) {
  return new TableRow({
    children: cols.map((col, i) => new TableCell({
      borders,
      width: { size: widths[i], type: WidthType.DXA },
      margins: cellMargins,
      children: [new Paragraph({ children: [new TextRun({ text: col, size: 20 })] })]
    }))
  });
}

const doc = new Document({
  styles: {
    default: { document: { run: { font: "Arial", size: 22 } } },
    paragraphStyles: [
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 36, bold: true, font: "Arial", color: DARK },
        paragraph: { spacing: { before: 360, after: 200 }, outlineLevel: 0 } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 28, bold: true, font: "Arial", color: DARK },
        paragraph: { spacing: { before: 280, after: 160 }, outlineLevel: 1 } },
      { id: "Heading3", name: "Heading 3", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 24, bold: true, font: "Arial", color: "333333" },
        paragraph: { spacing: { before: 200, after: 120 }, outlineLevel: 2 } },
    ]
  },
  numbering: {
    config: [
      { reference: "bullets", levels: [{ level: 0, format: LevelFormat.BULLET, text: "\u2022", alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] },
      { reference: "numbers", levels: [{ level: 0, format: LevelFormat.DECIMAL, text: "%1.", alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] },
      { reference: "numbers2", levels: [{ level: 0, format: LevelFormat.DECIMAL, text: "%1.", alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] },
      { reference: "numbers3", levels: [{ level: 0, format: LevelFormat.DECIMAL, text: "%1.", alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] },
      { reference: "bullets2", levels: [{ level: 0, format: LevelFormat.BULLET, text: "\u2022", alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] },
      { reference: "bullets3", levels: [{ level: 0, format: LevelFormat.BULLET, text: "\u2022", alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] },
      { reference: "bullets4", levels: [{ level: 0, format: LevelFormat.BULLET, text: "\u2022", alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] },
    ]
  },
  sections: [
    // ── COVER PAGE ──
    {
      properties: {
        page: {
          size: { width: 12240, height: 15840 },
          margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 }
        }
      },
      children: [
        new Paragraph({ spacing: { before: 3600 } }),
        new Paragraph({
          alignment: AlignmentType.CENTER,
          spacing: { after: 200 },
          children: [new TextRun({ text: "UPNEXT", size: 56, bold: true, color: ACCENT, font: "Arial" })]
        }),
        new Paragraph({
          alignment: AlignmentType.CENTER,
          spacing: { after: 400 },
          children: [new TextRun({ text: "Ship-Readiness Report", size: 40, color: DARK, font: "Arial" })]
        }),
        new Paragraph({
          alignment: AlignmentType.CENTER,
          spacing: { after: 100 },
          children: [new TextRun({ text: "Security Audit \u2022 Feature Gap Analysis \u2022 Multi-Location Plan", size: 22, color: GRAY })]
        }),
        new Paragraph({
          alignment: AlignmentType.CENTER,
          spacing: { after: 100 },
          children: [new TextRun({ text: "April 8, 2026", size: 22, color: GRAY })]
        }),
        new Paragraph({
          alignment: AlignmentType.CENTER,
          spacing: { before: 600 },
          border: { top: { style: BorderStyle.SINGLE, size: 2, color: ACCENT, space: 8 } },
          children: [new TextRun({ text: "Prepared for Carlos Canales \u2022 Fademasters Barbershop", size: 22, color: GRAY })]
        }),
      ]
    },

    // ── EXECUTIVE SUMMARY ──
    {
      properties: {
        page: {
          size: { width: 12240, height: 15840 },
          margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 }
        }
      },
      headers: {
        default: new Header({ children: [new Paragraph({
          border: { bottom: { style: BorderStyle.SINGLE, size: 1, color: ACCENT, space: 4 } },
          children: [new TextRun({ text: "UpNext Ship-Readiness Report", size: 18, color: GRAY, italics: true })]
        })] })
      },
      footers: {
        default: new Footer({ children: [new Paragraph({
          alignment: AlignmentType.CENTER,
          children: [new TextRun({ text: "Page ", size: 18, color: GRAY }), new TextRun({ children: [PageNumber.CURRENT], size: 18, color: GRAY })]
        })] })
      },
      children: [
        heading("Executive Summary"),
        para("UpNext is in strong shape. The core product (real-time queue management, SMS notifications, push alerts, subscription billing) is solid and production-worthy. However, there are a handful of security issues that MUST be fixed before you charge $50/month, plus some feature gaps that will help justify the price and reduce churn. Here\u2019s the honest breakdown:"),
        new Paragraph({ spacing: { after: 80 } }),
        
        new Table({
          width: { size: 9360, type: WidthType.DXA },
          columnWidths: [4680, 4680],
          rows: [
            new TableRow({ children: [
              new TableCell({ borders, width: { size: 4680, type: WidthType.DXA }, margins: cellMargins,
                shading: { fill: "FDEDEC", type: ShadingType.CLEAR },
                children: [
                  new Paragraph({ children: [new TextRun({ text: "3 Critical Security Fixes", bold: true, size: 22, color: RED })] }),
                  new Paragraph({ children: [new TextRun({ text: "Must fix before launch", size: 20, color: "666666" })] }),
                ]
              }),
              new TableCell({ borders, width: { size: 4680, type: WidthType.DXA }, margins: cellMargins,
                shading: { fill: "FEF9E7", type: ShadingType.CLEAR },
                children: [
                  new Paragraph({ children: [new TextRun({ text: "4 Warnings", bold: true, size: 22, color: ORANGE })] }),
                  new Paragraph({ children: [new TextRun({ text: "Fix within first 2 weeks", size: 20, color: "666666" })] }),
                ]
              }),
            ]}),
            new TableRow({ children: [
              new TableCell({ borders, width: { size: 4680, type: WidthType.DXA }, margins: cellMargins,
                shading: { fill: "EAFAF1", type: ShadingType.CLEAR },
                children: [
                  new Paragraph({ children: [new TextRun({ text: "Backup Server: Not Needed Yet", bold: true, size: 22, color: "27AE60" })] }),
                  new Paragraph({ children: [new TextRun({ text: "Firebase handles this for you", size: 20, color: "666666" })] }),
                ]
              }),
              new TableCell({ borders, width: { size: 4680, type: WidthType.DXA }, margins: cellMargins,
                shading: { fill: "EBF5FB", type: ShadingType.CLEAR },
                children: [
                  new Paragraph({ children: [new TextRun({ text: "Multi-Location: Planned Below", bold: true, size: 22, color: "2980B9" })] }),
                  new Paragraph({ children: [new TextRun({ text: "Full implementation roadmap included", size: 20, color: "666666" })] }),
                ]
              }),
            ]}),
          ]
        }),

        // ── SECTION 1: SECURITY ──
        new Paragraph({ children: [new PageBreak()] }),
        heading("1. Security Audit"),
        para("I went through every Firestore rule, every Cloud Function, your auth flow, and your API key exposure. Here\u2019s what I found:"),

        heading("1.1 Critical Issues (Fix Before Launch)", HeadingLevel.HEADING_2),

        new Table({
          width: { size: 9360, type: WidthType.DXA },
          columnWidths: [1200, 2400, 3360, 2400],
          rows: [
            headerRow(["Severity", "Issue", "What\u2019s Happening", "Fix"], [1200, 2400, 3360, 2400]),

            severityRow("CRITICAL", "Queue is wide open to writes",
              "firestore.rules has allow write: if true on /shops/{shopId}/queue/{entryId}. Anyone with your project ID can write ANY data to any shop\u2019s queue \u2014 fake check-ins, spam entries, or malicious data.",
              "Add field validation: require customerName (string, <100 chars), customerPhone (E.164 regex), status = \"waiting\" on create. Allow updates only from authenticated users."
            ),

            severityRow("CRITICAL", "Paywall bypass still active",
              "ContentView.swift line 27: paywallBypassed = true. If you ship with this, every owner gets the app for free. No revenue.",
              "Set paywallBypassed = false. Better yet, remove the flag entirely and use a #if DEBUG compiler flag so it can\u2019t accidentally ship."
            ),

            severityRow("CRITICAL", "No shop-scoped write rules",
              "Any authenticated user can write to ANY shop\u2019s barbers, services, settings, and queueHistory. A barber at Shop A could modify Shop B\u2019s data.",
              "Add rules that verify request.auth.uid belongs to a user document with matching shopId. Example: allow write if get(/databases/$(database)/documents/users/$(request.auth.uid)).data.shopId == shopId"
            ),
          ]
        }),

        heading("1.2 Warnings (Fix Within 2 Weeks)", HeadingLevel.HEADING_2),

        new Table({
          width: { size: 9360, type: WidthType.DXA },
          columnWidths: [1200, 2400, 3360, 2400],
          rows: [
            headerRow(["Severity", "Issue", "What\u2019s Happening", "Fix"], [1200, 2400, 3360, 2400]),

            severityRow("WARNING", "RevenueCat test key in production code",
              "UpNextApp.swift has test_XXhotbGXLwHaWrKfvhprjwOdRqK hardcoded. Test keys don\u2019t process real payments.",
              "Replace with your production public API key from RevenueCat Dashboard before App Store submission."
            ),

            severityRow("WARNING", "No rate limiting on queue writes",
              "Without rate limits, someone could spam thousands of fake check-ins via the kiosk or web check-in page.",
              "Add a Cloud Function that validates + throttles writes (max 1 check-in per phone number per 5 minutes)."
            ),

            severityRow("WARNING", "Customer phone numbers publicly readable",
              "Queue collection has allow read: if true. Anyone can read every customer\u2019s name and phone number from any shop\u2019s queue.",
              "Use Cloud Functions for the TV/kiosk display that return only names + positions (no phone numbers). Or add Firestore rules that filter sensitive fields."
            ),

            severityRow("WARNING", "No input sanitization on SMS",
              "Customer names flow directly into Twilio SMS templates. A malicious name like \"{name} - Reply STOP\" could confuse customers.",
              "Sanitize customerName in Cloud Functions: strip special chars, enforce max length (50 chars), validate phone format server-side."
            ),
          ]
        }),

        heading("1.3 What\u2019s Already Solid", HeadingLevel.HEADING_2),
        new Paragraph({ numbering: { reference: "bullets", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "Twilio credentials properly stored as Firebase Secrets (not in code)", size: 22 })] }),
        new Paragraph({ numbering: { reference: "bullets", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "Firebase Auth handles password hashing/salting automatically", size: 22 })] }),
        new Paragraph({ numbering: { reference: "bullets", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "FCM token cleanup removes stale tokens (no wasted pushes)", size: 22 })] }),
        new Paragraph({ numbering: { reference: "bullets", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "User documents properly scoped to own UID", size: 22 })] }),
        new Paragraph({ numbering: { reference: "bullets", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "Firebase API key in GoogleService-Info.plist is normal and expected (it\u2019s restricted by Firebase Security Rules, not secret)", size: 22 })] }),

        // ── SECTION 2: $50/MO VALUE ──
        new Paragraph({ children: [new PageBreak()] }),
        heading("2. Is UpNext Worth $50/Month?"),
        para("Short answer: yes, but barely. Here\u2019s the Hormozi lens on this \u2014 at $50/mo, a shop owner needs to feel like they\u2019d be stupid NOT to pay. Right now you have a strong core, but you\u2019re missing a few things that turn \"nice tool\" into \"can\u2019t live without it.\""),

        heading("2.1 What Already Justifies the Price", HeadingLevel.HEADING_2),
        new Paragraph({ numbering: { reference: "bullets2", level: 0 }, spacing: { after: 80 }, children: [
          new TextRun({ text: "Real-time queue management ", bold: true, size: 22 }),
          new TextRun({ text: "\u2014 this alone saves 30+ minutes/day of manual coordination", size: 22 })
        ]}),
        new Paragraph({ numbering: { reference: "bullets2", level: 0 }, spacing: { after: 80 }, children: [
          new TextRun({ text: "SMS notifications (Twilio) ", bold: true, size: 22 }),
          new TextRun({ text: "\u2014 customers love this. Reduces walk-outs by 20-40%", size: 22 })
        ]}),
        new Paragraph({ numbering: { reference: "bullets2", level: 0 }, spacing: { after: 80 }, children: [
          new TextRun({ text: "Kiosk check-in + TV queue display ", bold: true, size: 22 }),
          new TextRun({ text: "\u2014 professional, modern feel for the shop", size: 22 })
        ]}),
        new Paragraph({ numbering: { reference: "bullets2", level: 0 }, spacing: { after: 80 }, children: [
          new TextRun({ text: "Group check-in + party size ", bold: true, size: 22 }),
          new TextRun({ text: "\u2014 unique feature competitors don\u2019t have", size: 22 })
        ]}),
        new Paragraph({ numbering: { reference: "bullets2", level: 0 }, spacing: { after: 80 }, children: [
          new TextRun({ text: "Analytics dashboard ", bold: true, size: 22 }),
          new TextRun({ text: "\u2014 owners can see revenue, busiest days, barber leaderboard", size: 22 })
        ]}),

        heading("2.2 Gaps That Could Cause Churn", HeadingLevel.HEADING_2),
        para("These are the features that, if missing, will make shop owners cancel within 60 days:"),

        new Table({
          width: { size: 9360, type: WidthType.DXA },
          columnWidths: [2340, 3510, 1755, 1755],
          rows: [
            headerRow(["Feature Gap", "Why It Matters", "Effort", "Priority"], [2340, 3510, 1755, 1755]),
            simpleRow(["No owner signup flow in iOS", "Owners can only sign up via web. The App Store reviewer will reject an app with no way to create an account inside the app.", "Medium (1-2 weeks)", "Launch blocker"], [2340, 3510, 1755, 1755]),
            simpleRow(["No data export", "Owners WILL ask for CSV exports of their queue history and revenue data. Without it, they feel locked in.", "Small (2-3 days)", "Month 1"], [2340, 3510, 1755, 1755]),
            simpleRow(["No customer loyalty features", "Return customers get a greeting, but no rewards. A simple \"5th visit free\" or visit streak would massively increase perceived value.", "Medium (1-2 weeks)", "Month 1-2"], [2340, 3510, 1755, 1755]),
            simpleRow(["No offline fallback", "App relies 100% on Firestore with no local cache. If internet drops mid-day, the entire shop goes down.", "Medium (1-2 weeks)", "Month 1"], [2340, 3510, 1755, 1755]),
            simpleRow(["Limited analytics depth", "Current analytics are good but basic. Time-of-day heatmaps, customer retention rates, and revenue forecasting would justify the price at higher tiers.", "Medium (2-3 weeks)", "Month 2-3"], [2340, 3510, 1755, 1755]),
            simpleRow(["No in-app help/onboarding", "New shop owners need a guided setup. Without it, you\u2019ll spend hours on support calls.", "Small (1 week)", "Launch or Month 1"], [2340, 3510, 1755, 1755]),
          ]
        }),

        heading("2.3 Pricing Recommendation", HeadingLevel.HEADING_2),
        para("Your current tiers ($49/$79/$129) are solid. The $49 Starter tier is the sweet spot \u2014 it\u2019s less than what most shops spend on a single day\u2019s worth of missed walk-ins. One thing to consider: rename it from \"Starter\" to something that sounds less temporary. \"Essentials\" or \"Core\" keeps people from feeling like they need to upgrade immediately."),

        // ── SECTION 3: BACKUP SERVER ──
        new Paragraph({ children: [new PageBreak()] }),
        heading("3. Do You Need a Backup Server?"),
        
        para("No. Not right now, and probably not for a long time. Here\u2019s why:"),

        heading("3.1 Firebase Already Has Your Back", HeadingLevel.HEADING_2),
        new Paragraph({ numbering: { reference: "bullets3", level: 0 }, spacing: { after: 80 }, children: [
          new TextRun({ text: "Firestore replicates across multiple data centers automatically.", size: 22 }),
        ]}),
        new Paragraph({ numbering: { reference: "bullets3", level: 0 }, spacing: { after: 80 }, children: [
          new TextRun({ text: "99.999% uptime SLA on the Blaze plan. Google\u2019s infrastructure is more reliable than anything you\u2019d build yourself.", size: 22 }),
        ]}),
        new Paragraph({ numbering: { reference: "bullets3", level: 0 }, spacing: { after: 80 }, children: [
          new TextRun({ text: "Cloud Functions auto-scale. If you get 10 shops or 10,000 shops, Firebase handles the load.", size: 22 }),
        ]}),
        new Paragraph({ numbering: { reference: "bullets3", level: 0 }, spacing: { after: 80 }, children: [
          new TextRun({ text: "Firebase Auth, Storage, and Messaging are all managed services with built-in redundancy.", size: 22 }),
        ]}),

        heading("3.2 What You SHOULD Do Instead", HeadingLevel.HEADING_2),
        new Paragraph({ numbering: { reference: "numbers", level: 0 }, spacing: { after: 80 }, children: [
          new TextRun({ text: "Enable Firestore automated backups ", bold: true, size: 22 }),
          new TextRun({ text: "\u2014 Go to Firebase Console > Firestore > Backups. Set daily exports to a Cloud Storage bucket. This protects against accidental data deletion (your biggest real risk).", size: 22 }),
        ]}),
        new Paragraph({ numbering: { reference: "numbers", level: 0 }, spacing: { after: 80 }, children: [
          new TextRun({ text: "Set up Firebase Alerts ", bold: true, size: 22 }),
          new TextRun({ text: "\u2014 Get notified if your Cloud Functions start erroring, if Firestore usage spikes unexpectedly, or if your billing hits a threshold.", size: 22 }),
        ]}),
        new Paragraph({ numbering: { reference: "numbers", level: 0 }, spacing: { after: 80 }, children: [
          new TextRun({ text: "Set a billing budget cap ", bold: true, size: 22 }),
          new TextRun({ text: "\u2014 Protect yourself from a runaway bill if something goes wrong (like a spam bot hitting your queue). Set alerts at $50, $100, and $200.", size: 22 }),
        ]}),

        para("Bottom line: Firebase IS your backup server. The Tim Ferriss move here is to not build infrastructure you don\u2019t need. Revisit this when you hit 100+ shops."),

        // ── SECTION 4: MULTI-LOCATION ──
        new Paragraph({ children: [new PageBreak()] }),
        heading("4. Multi-Location Support"),
        para("This is the biggest feature add. Right now every user belongs to exactly one shop (single shopId field on AppUser). Here\u2019s how to do it without breaking what you already have:"),

        heading("4.1 Data Model Changes", HeadingLevel.HEADING_2),

        new Table({
          width: { size: 9360, type: WidthType.DXA },
          columnWidths: [2340, 3510, 3510],
          rows: [
            headerRow(["Model", "Current", "Multi-Location"], [2340, 3510, 3510]),
            simpleRow(["AppUser", "shopId: String (single shop)", "shopIds: [String] (array of shop IDs) + activeShopId: String (currently selected)"], [2340, 3510, 3510]),
            simpleRow(["Shop", "ownerId: String (single owner)", "ownerIds: [String] (array of owner UIDs for co-owners)"], [2340, 3510, 3510]),
            simpleRow(["Barber", "Lives under /shops/{shopId}/barbers", "No change \u2014 barbers stay shop-specific (a barber at Location A is different from Location B)"], [2340, 3510, 3510]),
            simpleRow(["Firestore Rules", "Check user.shopId == shopId", "Check shopId is in user.shopIds array"], [2340, 3510, 3510]),
          ]
        }),

        heading("4.2 New UI Components Needed", HeadingLevel.HEADING_2),
        new Paragraph({ numbering: { reference: "numbers2", level: 0 }, spacing: { after: 80 }, children: [
          new TextRun({ text: "Shop Switcher (Owner Dashboard) ", bold: true, size: 22 }),
          new TextRun({ text: "\u2014 A dropdown or bottom sheet that lets the owner switch between their locations. Store activeShopId in UserDefaults for persistence.", size: 22 }),
        ]}),
        new Paragraph({ numbering: { reference: "numbers2", level: 0 }, spacing: { after: 80 }, children: [
          new TextRun({ text: "\"Add Location\" Flow ", bold: true, size: 22 }),
          new TextRun({ text: "\u2014 Create a new Shop document, add its ID to the owner\u2019s shopIds array, copy default settings from their first location.", size: 22 }),
        ]}),
        new Paragraph({ numbering: { reference: "numbers2", level: 0 }, spacing: { after: 80 }, children: [
          new TextRun({ text: "Cross-Location Analytics ", bold: true, size: 22 }),
          new TextRun({ text: "\u2014 Aggregate view showing total revenue, total customers, and per-location breakdown. This is the killer feature for multi-location owners.", size: 22 }),
        ]}),
        new Paragraph({ numbering: { reference: "numbers2", level: 0 }, spacing: { after: 80 }, children: [
          new TextRun({ text: "Kiosk per Location ", bold: true, size: 22 }),
          new TextRun({ text: "\u2014 Each iPad stays locked to one shopId. No changes needed here \u2014 just deploy one iPad per location with a different shop code.", size: 22 }),
        ]}),

        heading("4.3 Migration Strategy", HeadingLevel.HEADING_2),
        para("The key is backward compatibility. Here\u2019s the safe path:"),
        new Paragraph({ numbering: { reference: "numbers3", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "Add shopIds array to AppUser (keep shopId as fallback for existing users)", size: 22 })] }),
        new Paragraph({ numbering: { reference: "numbers3", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "Add activeShopId to AppUser (default to current shopId)", size: 22 })] }),
        new Paragraph({ numbering: { reference: "numbers3", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "Update all ViewModels to read from activeShopId instead of shopId", size: 22 })] }),
        new Paragraph({ numbering: { reference: "numbers3", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "Write a Firestore migration function that populates shopIds = [shopId] for all existing users", size: 22 })] }),
        new Paragraph({ numbering: { reference: "numbers3", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "Add the shop switcher UI to OwnerTabView", size: 22 })] }),
        new Paragraph({ numbering: { reference: "numbers3", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "Gate multi-location behind the Pro tier ($79/mo) or higher", size: 22 })] }),

        heading("4.4 Estimated Timeline", HeadingLevel.HEADING_2),
        new Table({
          width: { size: 9360, type: WidthType.DXA },
          columnWidths: [3120, 3120, 3120],
          rows: [
            headerRow(["Phase", "Work", "Time"], [3120, 3120, 3120]),
            simpleRow(["Phase 1: Data model", "Add shopIds, activeShopId, update Firestore rules", "2-3 days"], [3120, 3120, 3120]),
            simpleRow(["Phase 2: Shop switcher UI", "Dropdown, \"Add Location\" flow, settings per location", "4-5 days"], [3120, 3120, 3120]),
            simpleRow(["Phase 3: Cross-location analytics", "Aggregate dashboard, per-location breakdown", "3-4 days"], [3120, 3120, 3120]),
            simpleRow(["Phase 4: Testing + migration", "Test with 2-3 test shops, run migration script", "2-3 days"], [3120, 3120, 3120]),
            simpleRow(["TOTAL", "", "2-3 weeks"], [3120, 3120, 3120]),
          ]
        }),

        // ── SECTION 5: LAUNCH CHECKLIST ──
        new Paragraph({ children: [new PageBreak()] }),
        heading("5. Launch Checklist"),
        para("Here\u2019s your ordered list of what to do, from \"do this tonight\" to \"do this in month 2\":"),

        heading("5.1 Before App Store Submission", HeadingLevel.HEADING_2),
        new Paragraph({ numbering: { reference: "bullets4", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "Set paywallBypassed = false (or remove it entirely)", size: 22 })] }),
        new Paragraph({ numbering: { reference: "bullets4", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "Replace RevenueCat test key with production key", size: 22 })] }),
        new Paragraph({ numbering: { reference: "bullets4", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "Lock down Firestore queue writes with field validation", size: 22 })] }),
        new Paragraph({ numbering: { reference: "bullets4", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "Add shop-scoped write rules (user must belong to the shop)", size: 22 })] }),
        new Paragraph({ numbering: { reference: "bullets4", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "Enable Firestore daily backups", size: 22 })] }),
        new Paragraph({ numbering: { reference: "bullets4", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "Set Firebase billing alerts ($50/$100/$200)", size: 22 })] }),
        new Paragraph({ numbering: { reference: "bullets4", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "Add owner signup flow to the iOS app (App Store requirement)", size: 22 })] }),
        new Paragraph({ numbering: { reference: "bullets4", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "Test subscription purchase + restore flow with sandbox Apple ID", size: 22 })] }),

        heading("5.2 First 2 Weeks After Launch", HeadingLevel.HEADING_2),
        new Paragraph({ numbering: { reference: "bullets4", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "Add rate limiting on queue check-ins", size: 22 })] }),
        new Paragraph({ numbering: { reference: "bullets4", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "Add input sanitization on customer names in Cloud Functions", size: 22 })] }),
        new Paragraph({ numbering: { reference: "bullets4", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "Remove phone numbers from public Firestore reads", size: 22 })] }),
        new Paragraph({ numbering: { reference: "bullets4", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "Add Firestore offline persistence (enablePersistence) as fallback", size: 22 })] }),

        heading("5.3 Month 1-2 (Post-Launch)", HeadingLevel.HEADING_2),
        new Paragraph({ numbering: { reference: "bullets4", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "Multi-location support (Phase 1-4 above)", size: 22 })] }),
        new Paragraph({ numbering: { reference: "bullets4", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "CSV data export for owners", size: 22 })] }),
        new Paragraph({ numbering: { reference: "bullets4", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "Customer loyalty / visit streak feature", size: 22 })] }),
        new Paragraph({ numbering: { reference: "bullets4", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "Enhanced analytics (heatmaps, retention, forecasting)", size: 22 })] }),
        new Paragraph({ numbering: { reference: "bullets4", level: 0 }, spacing: { after: 80 }, children: [new TextRun({ text: "In-app onboarding guide for new shop owners", size: 22 })] }),

        new Paragraph({ spacing: { before: 400 }, border: { top: { style: BorderStyle.SINGLE, size: 2, color: ACCENT, space: 8 } } }),
        para("You\u2019re closer than you think, Carlos. The foundation is rock solid \u2014 the Firebase architecture, the real-time queue, the SMS flow, the subscription model. Fix the 3 critical security items, swap out the test keys, and you\u2019ve got a legit product people will pay for. The multi-location stuff and the nice-to-haves can come in updates. Ship it."),
      ]
    }
  ]
});

Packer.toBuffer(doc).then(buffer => {
  fs.writeFileSync("/sessions/gifted-kind-gauss/mnt/UpNext/UpNext-Ship-Readiness-Report.docx", buffer);
  console.log("Report created successfully!");
});
