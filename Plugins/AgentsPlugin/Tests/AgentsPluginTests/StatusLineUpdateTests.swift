import Foundation
import Testing
@testable import AgentsPlugin

struct StatusLineUpdateTests {
    @Test func decodesTheDocumentedStatusLine() throws {
        let update = try StatusLineUpdate.decode(Data(Self.documentedExample.utf8))
        #expect(update.sessionID == "abc123...")
        #expect(update.sessionName == "my-session")
        #expect(update.details == SessionDetails(
            contextPercentage: 8,
            model: "Opus",
            effort: "high",
            fastMode: false,
            worktree: "my-feature",
            pullRequest: SessionDetails.PullRequest(number: 1234, url: "https://github.com/anthropics/claude-code/pull/1234", reviewState: "pending", isMergeRequest: false)
        ))
        #expect(update.details.badgeText == "Opus · high")
        #expect(update.details.pullRequest?.help == "Pull request #1234: pending")
        #expect(update.usage?.fiveHour?.utilization == 23.5)
        #expect(update.usage?.sevenDay?.utilization == 41.2)
    }

    @Test func nullContextAndMissingEffortLeaveThoseFieldsUnset() throws {
        let nullPercentage = try StatusLineUpdate.decode(Data(#"{"session_id":"s","context_window":{"used_percentage":null},"model":{"display_name":"Opus"},"effort":{"level":"high"},"fast_mode":false}"#.utf8))
        #expect(nullPercentage.details.contextPercentage == nil)
        #expect(nullPercentage.details.model == "Opus")

        let missingEffort = try StatusLineUpdate.decode(Data(#"{"session_id":"s","model":{"display_name":"Opus 4.7"},"fast_mode":true,"context_window":{"used_percentage":12}}"#.utf8))
        #expect(missingEffort.details == SessionDetails(contextPercentage: 12, model: "Opus 4.7", effort: nil, fastMode: true))
        #expect(missingEffort.details.badgeText == "Opus 4.7 · fast")

        let zero = try StatusLineUpdate.decode(Data(#"{"session_id":"s","context_window":{"used_percentage":0}}"#.utf8))
        let one = try StatusLineUpdate.decode(Data(#"{"session_id":"s","context_window":{"used_percentage":1}}"#.utf8))
        let onePoint = try StatusLineUpdate.decode(Data(#"{"session_id":"s","context_window":{"used_percentage":1.0}}"#.utf8))
        let flag = try StatusLineUpdate.decode(Data(#"{"session_id":"s","context_window":{"used_percentage":true}}"#.utf8))
        #expect(zero.details.contextPercentage == 0)
        #expect(one.details.contextPercentage == 1)
        #expect(onePoint.details.contextPercentage == 1)
        #expect(flag.details.contextPercentage == nil)
    }

    @Test func decodesWorktreesAndPullRequests() throws {
        let linked = try StatusLineUpdate.decode(Data(#"{"session_id":"s","workspace":{"git_worktree":"feature-xyz"}}"#.utf8))
        #expect(linked.details.worktree == "feature-xyz")
        #expect(linked.details.pullRequest == nil)

        let named = try StatusLineUpdate.decode(Data(#"{"session_id":"s","worktree":{"name":"my-feature"},"workspace":{"git_worktree":"feature-xyz"},"pr":{"number":12,"url":"https://example.com/12","review_state":"approved"}}"#.utf8))
        #expect(named.details.worktree == "my-feature")
        #expect(named.details.pullRequest == SessionDetails.PullRequest(number: 12, url: "https://example.com/12", reviewState: "approved", isMergeRequest: false))

        let mergeRequest = try StatusLineUpdate.decode(Data(#"{"session_id":"s","pr":{"number":7,"url":"https://gitlab.com/group/proj/-/merge_requests/7","kind":"mr"}}"#.utf8))
        #expect(mergeRequest.details.pullRequest == SessionDetails.PullRequest(number: 7, url: "https://gitlab.com/group/proj/-/merge_requests/7", reviewState: nil, isMergeRequest: true))
        #expect(mergeRequest.details.pullRequest?.label == "!7")
        #expect(mergeRequest.details.pullRequest?.help == "Merge request !7")

        let absent = try StatusLineUpdate.decode(Data(#"{"session_id":"s"}"#.utf8))
        #expect(absent.details.worktree == nil)
        #expect(absent.details.pullRequest == nil)
    }

    private static let documentedExample = """
    {
      "cwd": "/current/working/directory",
      "session_id": "abc123...",
      "session_name": "my-session",
      "prompt_id": "550e8400-e29b-41d4-a716-446655440000",
      "transcript_path": "/path/to/transcript.jsonl",
      "model": {
        "id": "claude-opus-5",
        "display_name": "Opus"
      },
      "workspace": {
        "current_dir": "/current/working/directory",
        "project_dir": "/original/project/directory",
        "added_dirs": [],
        "git_worktree": "feature-xyz",
        "repo": {
          "host": "github.com",
          "owner": "anthropics",
          "name": "claude-code"
        }
      },
      "version": "2.1.90",
      "output_style": {
        "name": "default"
      },
      "cost": {
        "total_cost_usd": 0.01234,
        "total_duration_ms": 45000,
        "total_api_duration_ms": 2300,
        "total_lines_added": 156,
        "total_lines_removed": 23
      },
      "context_window": {
        "total_input_tokens": 15500,
        "total_output_tokens": 1200,
        "context_window_size": 200000,
        "used_percentage": 8,
        "remaining_percentage": 92,
        "current_usage": {
          "input_tokens": 8500,
          "output_tokens": 1200,
          "cache_creation_input_tokens": 5000,
          "cache_read_input_tokens": 2000
        }
      },
      "exceeds_200k_tokens": false,
      "fast_mode": false,
      "effort": {
        "level": "high"
      },
      "thinking": {
        "enabled": true
      },
      "rate_limits": {
        "five_hour": {
          "used_percentage": 23.5,
          "resets_at": 1738425600
        },
        "seven_day": {
          "used_percentage": 41.2,
          "resets_at": 1738857600
        }
      },
      "vim": {
        "mode": "NORMAL"
      },
      "agent": {
        "name": "security-reviewer"
      },
      "pr": {
        "number": 1234,
        "url": "https://github.com/anthropics/claude-code/pull/1234",
        "review_state": "pending"
      },
      "worktree": {
        "name": "my-feature",
        "path": "/path/to/.claude/worktrees/my-feature",
        "branch": "worktree-my-feature",
        "original_cwd": "/path/to/project",
        "original_branch": "main"
      }
    }
    """
}
