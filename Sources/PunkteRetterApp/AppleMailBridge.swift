#if os(macOS)
import Foundation

struct MailAccountChoice: Identifiable, Hashable {
    let accountID: String
    let displayName: String
    let senderAddress: String
    var id: String { accountID + "|" + senderAddress.lowercased() }
}

enum AppleMailError: LocalizedError {
    case script(String), accountMissing, senderMismatch
    var errorDescription: String? {
        switch self {
        case .script(let s): return "Apple Mail konnte nicht verwendet werden: \(s)"
        case .accountMissing: return "Das ausgewählte Versandkonto ist in Apple Mail nicht mehr vorhanden."
        case .senderMismatch: return "Apple Mail würde die Nachricht nicht mit dem ausgewählten Absenderkonto erstellen."
        }
    }
}

enum AppleMailBridge {
    private static let appleScriptSuite: AEEventClass = 0x61736372 // 'ascr'
    private static let subroutineEventID: AEEventID = 0x70736272 // 'psbr'
    private static let subroutineNameKeyword: AEKeyword = 0x736e616d // 'snam'
    private static let directObjectKeyword: AEKeyword = 0x2d2d2d2d // '----'

    private static func subroutineEvent(name: String, args: [String]) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: appleScriptSuite,
            eventID: subroutineEventID,
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(NSAppleEventDescriptor(string: name), forKeyword: subroutineNameKeyword)
        let list = NSAppleEventDescriptor.list()
        for (index, value) in args.enumerated() {
            list.insert(NSAppleEventDescriptor(string: value), at: index + 1)
        }
        event.setParam(list, forKeyword: directObjectKeyword)
        return event
    }

    private static func run(script source: String, handler: String, args: [String]) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else { throw AppleMailError.script("Skript konnte nicht vorbereitet werden.") }
        var compileError: NSDictionary?
        script.compileAndReturnError(&compileError)
        if let compileError { throw AppleMailError.script(compileError.description) }
        var error: NSDictionary?
        let result = script.executeAppleEvent(subroutineEvent(name: handler, args: args), error: &error)
        if let error { throw AppleMailError.script(error[NSAppleScript.errorMessage] as? String ?? error.description) }
        return result
    }

    static func accounts() throws -> [MailAccountChoice] {
        let source = #"""
        on listAccounts()
            set rows to {}
            with timeout of 20 seconds
                tell application "Mail"
                    repeat with a in every account
                        try
                            set aid to id of a as text
                            set aname to name of a as text
                            set addrs to email addresses of a
                            repeat with addr in addrs
                                set end of rows to {aid, aname, addr as text}
                            end repeat
                        end try
                    end repeat
                end tell
            end timeout
            return rows
        end listAccounts
        """#
        let result = try run(script: source, handler: "listAccounts", args: [])
        let count = result.numberOfItems
        guard count > 0 else { return [] }

        var out: [MailAccountChoice] = []
        for i in 1...count {
            guard let row = result.atIndex(i), row.numberOfItems >= 3,
                  let id = row.atIndex(1)?.stringValue,
                  let name = row.atIndex(2)?.stringValue,
                  let addr = row.atIndex(3)?.stringValue else { continue }
            out.append(MailAccountChoice(accountID: id, displayName: name, senderAddress: addr))
        }
        return out
    }

    static func send(accountID: String, senderAddress: String, to: String, subject: String, body: String) throws {
        let source = #"""
        on sendFromAccount(accountID, senderAddress, recipientAddress, subjectText, bodyText)
            with timeout of 35 seconds
                tell application "Mail"
                    set matches to every account whose id is accountID
                    if (count of matches) is 0 then error "Das ausgewählte Apple-Mail-Konto existiert nicht mehr."
                    set acct to item 1 of matches
                    if (email addresses of acct) does not contain senderAddress then error "Die ausgewählte Absenderadresse gehört nicht mehr zu diesem Konto."
                    set m to make new outgoing message with properties {visible:false, subject:subjectText, content:bodyText, sender:senderAddress}
                    tell m to make new to recipient at end of to recipients with properties {address:recipientAddress}
                    set effectiveSender to sender of m as text
                    ignoring case
                        if effectiveSender does not contain senderAddress then
                            delete m
                            error "Apple Mail hat ein anderes Absenderkonto gewählt. Versand wurde abgebrochen."
                        end if
                    end ignoring
                    send m
                    return effectiveSender
                end tell
            end timeout
        end sendFromAccount
        """#
        _ = try run(script: source, handler: "sendFromAccount", args: [accountID, senderAddress, to, subject, body])
    }
}
#endif
