#if os(macOS)
import Foundation

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

    private static func run(_ source: String, handler: String, args: [String]) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else {
            throw NSError(domain: "PunkteRetter.Mail", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mail-Automation konnte nicht vorbereitet werden."])
        }
        var compileError: NSDictionary?
        script.compileAndReturnError(&compileError)
        if let compileError {
            throw NSError(domain: "PunkteRetter.Mail", code: 2, userInfo: [NSLocalizedDescriptionKey: compileError.description])
        }
        var error: NSDictionary?
        let result = script.executeAppleEvent(subroutineEvent(name: handler, args: args), error: &error)
        if let error {
            let number = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue
            let message: String
            switch number {
            case -1712:
                message = "Apple Mail hat innerhalb des vorgesehenen Zeitlimits nicht geantwortet."
            case -1743:
                message = "macOS hat den Zugriff auf Apple Mail nicht erlaubt. Bitte die Automatisierungsfreigabe prüfen."
            default:
                message = error[NSAppleScript.errorMessage] as? String ?? error.description
            }
            throw NSError(domain: "PunkteRetter.Mail", code: number ?? 3, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return result
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
                            error "Apple Mail hat ein anderes Absenderkonto gewählt."
                        end if
                    end ignoring
                    send m
                    return "handed-to-mail"
                end tell
            end timeout
        end sendFromAccount
        """#
        let result = try run(source, handler: "sendFromAccount", args: [accountID, senderAddress, to, subject, body])
        guard result.stringValue == "handed-to-mail" else {
            throw NSError(domain: "PunkteRetter.Mail", code: 4, userInfo: [NSLocalizedDescriptionKey: "Apple Mail hat die Übergabe der Nachricht nicht bestätigt."])
        }
    }
}
#endif
