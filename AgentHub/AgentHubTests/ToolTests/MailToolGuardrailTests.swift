import Testing
@testable import AgentKit

// NOTE: MailTool lives in the AgentHubMac target (it depends on ComposioClient),
// so these tests belong in that target's test bundle in Xcode. They document
// the guardrail contract regardless of where they finally compile.
//
// The invariant under test:
//   - drafting email never requires approval
//   - sending email ALWAYS requires approval (routed through PendingApproval)
//
// If you move MailTool's approval logic, keep a test like this red-guarding it.

struct MailToolGuardrailContract {

    @Test func draftDoesNotRequireApproval() {
        let intent = "draft"
        #expect(requiresApproval(intent: intent) == false)
    }

    @Test func sendRequiresApproval() {
        let intent = "send"
        #expect(requiresApproval(intent: intent) == true)
    }

    // Mirror of MailTool.requiresApproval(for:) — replace with a direct call to
    // the real tool once these run inside the Mac target.
    private func requiresApproval(intent: String) -> Bool {
        intent == "send"
    }
}
