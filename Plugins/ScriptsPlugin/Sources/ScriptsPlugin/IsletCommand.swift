import Foundation

struct IsletCommand: Sendable, Equatable {
    static let fileName = "islet"
    static let marker = "islet_cli=1"

    let port: UInt16
    let tokenFile: URL
    let directory: URL

    init(port: UInt16, tokenFile: URL, directory: URL = URL.homeDirectory.appending(path: ".local/bin", directoryHint: .isDirectory)) {
        self.port = port
        self.tokenFile = tokenFile
        self.directory = directory
    }

    var url: URL {
        directory.appending(path: Self.fileName)
    }

    var isInstalled: Bool {
        (try? String(contentsOf: url, encoding: .utf8))?.contains(Self.marker) == true
    }

    func install() throws {
        if FileManager.default.fileExists(atPath: url.path), !isInstalled {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSLocalizedDescriptionKey: "\(url.path) already exists and was not installed by Islet."])
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(script.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    func uninstall() throws {
        guard isInstalled else { return }
        try FileManager.default.removeItem(at: url)
    }

    private static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    var script: String {
        #"""
        #!/bin/sh
        \#(Self.marker)
        port=\#(port)
        token_file=\#(Self.quoted(tokenFile.path))
        quiet=0

        usage() {
          cat >&2 <<'ISLET_USAGE'
        usage: islet announce TEXT [--symbol S] [--priority P]
               islet activity ID TEXT [--symbol S] [--priority P] [--ttl SECONDS]
               islet progress ID VALUE TEXT
               islet done ID [TEXT]
               islet clear ID
               islet run ID -- COMMAND...
        ISLET_USAGE
          exit 2
        }

        escape() {
          tab=$(printf '\t')
          cr=$(printf '\r')
          printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/$tab/\\\\t/g" -e "s/$cr/\\\\r/g" | sed -e ':a' -e '$!N' -e '$!ba' -e 's/\n/\\n/g'
        }

        is_number() {
          [ -n "$(printf '%s' "$1" | sed -n '/^[0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}$/p')" ]
        }

        check_id() {
          case "$1" in ""|*[!A-Za-z0-9._-]*) usage ;; esac
        }

        call() {
          if [ ! -r "$token_file" ]; then
            [ "$quiet" = 1 ] || echo "islet: Islet is not running" >&2
            quiet=1
            return 1
          fi
          token=$(cat "$token_file")
          if [ -n "$3" ]; then
            printf 'header = "Authorization: Bearer %s"\n' "$token" | curl -sf --connect-timeout 1 -m 5 -K - -X "$1" -H "Content-Type: application/json" -H "Expect:" --data-binary "$3" "http://127.0.0.1:$port$2" >/dev/null 2>&1
          else
            printf 'header = "Authorization: Bearer %s"\n' "$token" | curl -sf --connect-timeout 1 -m 5 -K - -X "$1" "http://127.0.0.1:$port$2" >/dev/null 2>&1
          fi
          status=$?
          if [ "$status" -ne 0 ]; then
            [ "$quiet" = 1 ] || echo "islet: could not reach Islet on 127.0.0.1:$port" >&2
            quiet=1
            return 1
          fi
        }

        options() {
          extra=""
          while [ $# -gt 0 ]; do
            [ $# -ge 2 ] || usage
            case "$1" in
              --symbol) extra="$extra,\"symbol\":\"$(escape "$2")\"" ;;
              --priority) extra="$extra,\"priority\":\"$(escape "$2")\"" ;;
              --ttl) if [ "$allow_ttl" = 1 ] && is_number "$2"; then extra="$extra,\"ttl\":$2"; else usage; fi ;;
              *) usage ;;
            esac
            shift 2
          done
        }

        percent() {
          value="${1%\%}"
          if [ "$value" = "$1" ]; then
            is_number "$1" || usage
            printf '%s' "$1"
            return
          fi
          is_number "$value" || usage
          whole="${value%%.*}"
          fraction=""
          case "$value" in *.*) fraction="${value#*.}" ;; esac
          whole=$(printf '%s' "$whole" | sed 's/^0*//')
          while [ "${#whole}" -lt 3 ]; do whole="0$whole"; done
          head="${whole%??}"
          tail="${whole#"$head"}"
          printf '%s.%s%s' "${head#0}" "$tail" "$fraction" | sed 's/^\./0./'
        }

        [ $# -ge 1 ] || usage
        command="$1"
        shift
        allow_ttl=0
        case "$command" in
          announce)
            [ $# -ge 1 ] || usage
            text="$1"
            shift
            options "$@"
            call POST /announce "{\"text\":\"$(escape "$text")\"$extra}"
            ;;
          activity)
            [ $# -ge 2 ] || usage
            check_id "$1"
            id="$1"
            text="$2"
            shift 2
            allow_ttl=1
            options "$@"
            call POST /activity "{\"id\":\"$id\",\"text\":\"$(escape "$text")\"$extra}"
            ;;
          progress)
            [ $# -eq 3 ] || usage
            check_id "$1"
            value=$(percent "$2") || exit 2
            call POST /activity "{\"id\":\"$1\",\"text\":\"$(escape "$3")\",\"progress\":$value}"
            ;;
          done)
            [ $# -ge 1 ] && [ $# -le 2 ] || usage
            check_id "$1"
            id="$1"
            text="${2:-$id finished}"
            call DELETE "/activity/$id"
            call POST /announce "{\"text\":\"$(escape "$text")\"}"
            ;;
          clear)
            [ $# -eq 1 ] || usage
            check_id "$1"
            call DELETE "/activity/$1"
            ;;
          run)
            [ $# -ge 3 ] && [ "$2" = "--" ] || usage
            check_id "$1"
            id="$1"
            shift 2
            call POST /activity "{\"id\":\"$id\",\"text\":\"$(escape "Running $*")\",\"ttl\":86400}"
            trap : INT
            "$@"
            code=$?
            trap - INT
            call DELETE "/activity/$id"
            if [ "$code" -eq 0 ]; then
              call POST /announce "{\"text\":\"$(escape "$id finished")\"}"
            else
              call POST /announce "{\"text\":\"$(escape "$id failed (exit $code)")\",\"priority\":\"attention\"}"
            fi
            exit "$code"
            ;;
          *)
            usage
            ;;
        esac
        """#
    }
}
