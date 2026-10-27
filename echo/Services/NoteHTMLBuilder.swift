import Foundation

/// A single transcription added to a notes-mode session, optionally paired with
/// the screenshot taken when its recording stopped.
struct NoteEntry: Identifiable {
  let id = UUID()
  let timestamp: Date
  let text: String
  let screenshotFileName: String?
}

/// Renders a notes-mode session as a self-contained HTML document plus a markdown
/// companion file. Screenshots are referenced relatively from an `images/` folder
/// next to the exported files. The HTML offers three views of the note — the full
/// note with screenshots, the plain transcript, and an LLM-cleaned version — each
/// copyable to the clipboard (as text or as rich HTML for pasting into email and chat
/// apps), along with a change title and the markdown file's path.
enum NoteHTMLBuilder {
  /// All transcriptions joined into a single plain-text transcript.
  static func plainTranscript(entries: [NoteEntry]) -> String {
    entries.map(\.text).joined(separator: "\n\n")
  }

  /// The note as markdown: each entry's text followed by its embedded screenshot image.
  static func renderMarkdown(entries: [NoteEntry], startedAt: Date) -> String {
    let titleFormatter = DateFormatter()
    titleFormatter.dateStyle = .full
    titleFormatter.timeStyle = .short

    var lines = ["# Echo Note — \(titleFormatter.string(from: startedAt))", ""]
    for entry in entries {
      lines.append(entry.text)
      lines.append("")
      if let fileName = entry.screenshotFileName {
        lines.append("![Screenshot](images/\(fileName))")
        lines.append("")
      }
    }
    return lines.joined(separator: "\n")
  }

  static func render(
    entries: [NoteEntry],
    startedAt: Date,
    cleanedText: String?,
    markdownFilePath: String,
    changeTitle: String?,
    screenshots: [String: Data] = [:]
  ) -> String {
    let titleFormatter = DateFormatter()
    titleFormatter.dateStyle = .full
    titleFormatter.timeStyle = .short
    let title = changeTitle ?? "Echo Note — \(titleFormatter.string(from: startedAt))"

    let entriesHTML = entries.map { entry -> String in
      var block = """
            <article class="entry">
              <p class="entry-text">\(escape(entry.text))</p>
        """
      if let fileName = entry.screenshotFileName,
        let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
      {
        block += """

              <a class="shot" href="images/\(encoded)" target="_blank">
                <img class="entry-screenshot" src="images/\(encoded)" alt="Screenshot" loading="lazy">
              </a>
          """
      }
      block += "\n    </article>"
      return block
    }.joined(separator: "\n")

    let transcript = plainTranscript(entries: entries)

    let cleanedHTML: String
    if let cleanedText {
      cleanedHTML = """
            <article class="entry">
              <p class="entry-text">\(escape(cleanedText))</p>
            </article>
        """
    } else {
      cleanedHTML = """
            <article class="entry">
              <p class="entry-text unavailable">A cleaned-up version could not be generated for this note (post-processing failed or no API key is configured).</p>
            </article>
        """
    }

    let copyData = copyDataJSON(
      noteMarkdown: renderMarkdown(entries: entries, startedAt: startedAt),
      noteHTML: renderClipboardHTML(
        entries: entries, startedAt: startedAt, title: title, screenshots: screenshots
      ),
      transcript: transcript,
      cleaned: cleanedText,
      markdownReference: "\(title)\n\(markdownFilePath)"
    )

    return """
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Echo Note — \(escape(titleFormatter.string(from: startedAt)))</title>
        <link rel="preconnect" href="https://fonts.googleapis.com">
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
        <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Instrument+Sans:wght@400;500;600&family=Newsreader:opsz,wght@6..72,500&display=swap">
        <style>
          /* One reading column: copy buttons, title, then entries separated by hairlines.
             Only class selectors are used so nothing here can reach the hidden copy source. */
          :root {
            color-scheme: light dark;
            --bg: #ffffff;
            --ink: #15171c;
            --muted: #646975;
            --line: #e7e8ec;
            --wash: #f6f7f9;
            --focus: #2f5bd3;
            --display: "Newsreader", Georgia, "Times New Roman", serif;
            --text: "Instrument Sans", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
          }
          @media (prefers-color-scheme: dark) {
            :root {
              --bg: #111214;
              --ink: #ececef;
              --muted: #9ea2ad;
              --line: #26282e;
              --wash: #1a1b1f;
              --focus: #7a9bff;
            }
          }
          .page, .page * { box-sizing: border-box; }
          html, body { background: var(--bg); color: var(--ink); }
          body {
            margin: 0;
            font-family: var(--text);
            font-size: 17px;
            line-height: 1.6;
            -webkit-font-smoothing: antialiased;
            text-rendering: optimizeLegibility;
          }
          .page { max-width: 760px; margin: 0 auto; padding: 32px 20px 96px; }
          .bar { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: 6px; }
          .action-btn {
            display: inline-flex;
            align-items: center;
            gap: 7px;
            font: 500 13px/1 var(--text);
            color: var(--ink);
            background: var(--bg);
            border: 1px solid var(--line);
            border-radius: 7px;
            padding: 8px 12px;
            cursor: pointer;
            transition: background 0.15s, border-color 0.15s;
          }
          .action-btn::before {
            content: "";
            width: 14px;
            height: 14px;
            flex: none;
            background: var(--muted);
            -webkit-mask: var(--copy-icon) center / contain no-repeat;
            mask: var(--copy-icon) center / contain no-repeat;
            --copy-icon: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16' fill='none' stroke='black' stroke-width='1.4'%3E%3Crect x='5.5' y='5.5' width='8' height='8' rx='1.5'/%3E%3Cpath d='M10.5 3.5v-.5A1.5 1.5 0 0 0 9 1.5H4A1.5 1.5 0 0 0 2.5 3v5A1.5 1.5 0 0 0 4 9.5h.5'/%3E%3C/svg%3E");
          }
          .action-btn:hover { background: var(--wash); }
          .action-btn:disabled { cursor: default; }
          .action-btn:disabled::before { background: var(--focus); }
          .action-btn:focus-visible, .seg-btn:focus-visible, .shot:focus-visible {
            outline: 2px solid var(--focus);
            outline-offset: 2px;
          }
          .masthead { margin-top: 40px; }
          .change-title {
            font-family: var(--display);
            font-weight: 500;
            font-size: clamp(32px, 6vw, 44px);
            line-height: 1.12;
            letter-spacing: -0.012em;
            overflow-wrap: anywhere;
          }
          .subtitle { margin-top: 12px; color: var(--muted); font-size: 15px; }
          .segmented { display: flex; gap: 22px; margin-top: 32px; border-bottom: 1px solid var(--line); }
          .seg-btn {
            border: 0;
            border-bottom: 2px solid transparent;
            margin-bottom: -1px;
            background: none;
            color: var(--muted);
            font: 500 15px/1 var(--text);
            padding: 0 0 12px;
            cursor: pointer;
          }
          .seg-btn:hover { color: var(--ink); }
          .seg-btn.active { color: var(--ink); border-bottom-color: var(--ink); }
          .view { display: none; }
          .view.active { display: block; }
          .entry { display: grid; gap: 18px; padding-block: 32px; border-bottom: 1px solid var(--line); }
          .entry:last-child { border-bottom: 0; }
          .entry-text { margin: 0; white-space: pre-wrap; overflow-wrap: anywhere; }
          .entry-text.unavailable { color: var(--muted); }
          .shot {
            display: block;
            border: 1px solid var(--line);
            border-radius: 8px;
            overflow: hidden;
            background: var(--wash);
          }
          .entry-screenshot { display: block; width: 100%; height: auto; }
          /* The Copy HTML source. Browsers serialize the styles they compute for a copied
             selection, so the source must not inherit the page's theme: `all: initial` cuts
             inheritance and the fixed values below give the pasted content a neutral,
             transparent, light-scheme context that Gmail can restyle freely. */
          .copy-source {
            all: initial;
            display: block;
            position: absolute;
            left: -10000px;
            top: 0;
            width: 760px;
            pointer-events: none;
            color-scheme: light;
            color: #222222;
            background: transparent;
            font: 14px/1.5 Arial, Helvetica, sans-serif;
          }
          @media (prefers-reduced-motion: reduce) { .action-btn { transition: none; } }
        </style>
      </head>
      <body>
        <main class="page">
          <div class="bar">
            <button class="action-btn" id="copy-html" title="Copy formatted text and, in Note view, screenshots to paste into email or chat apps">Copy HTML</button>
            <button class="action-btn" id="copy-content" title="Copy the note as Markdown">Copy Markdown</button>
            <button class="action-btn" id="copy-md-path" title="Copy the change title and the path of the Markdown file saved next to this page">Copy Path</button>
          </div>
          <header class="masthead">
            <div class="change-title">\(escape(title))</div>
            <div class="subtitle">\(escape(titleFormatter.string(from: startedAt)))</div>
          </header>
          <div class="segmented" role="tablist">
            <button class="seg-btn active" data-view="note">Note</button>
            <button class="seg-btn" data-view="transcript">Transcript</button>
            <button class="seg-btn" data-view="cleaned">Cleaned Up</button>
          </div>
          <section class="view active" id="view-note">
      \(entriesHTML)
          </section>
          <section class="view" id="view-transcript">
            <article class="entry">
              <p class="entry-text">\(escape(transcript))</p>
            </article>
          </section>
          <section class="view" id="view-cleaned">
      \(cleanedHTML)
          </section>
        </main>
        <script id="copy-data" type="application/json">\(copyData)</script>
        <script>
          const copyData = JSON.parse(document.getElementById('copy-data').textContent);
          let currentView = 'note';

          // Preload embedded PNGs before the click so selection copying stays inside
          // the user gesture. Safari packages the loaded resources in a WebArchive:
          // https://webkit.org/blog/8170/clipboard-api-improvements/
          //
          // Every rendered-selection source comes from createCopySource, which gives the
          // markup the neutral .copy-source context instead of the themed page body.
          function createCopySource(html) {
            const source = document.createElement('div');
            source.className = 'copy-source';
            source.setAttribute('aria-hidden', 'true');
            source.innerHTML = html;
            document.body.appendChild(source);
            return source;
          }

          const noteCopySource = createCopySource(copyData.noteHTML);
          const noteCopyImages = Array.from(noteCopySource.querySelectorAll('img'));
          let noteImagesReady = noteCopyImages.length === 0;
          let noteImagesFailed = false;
          Promise.all(noteCopyImages.map((image) => image.decode())).then(() => {
            noteImagesReady = true;
          }).catch(() => {
            noteImagesFailed = true;
          });

          document.querySelectorAll('.seg-btn').forEach((btn) => {
            btn.addEventListener('click', () => {
              currentView = btn.dataset.view;
              document.querySelectorAll('.seg-btn').forEach((b) => {
                b.classList.toggle('active', b === btn);
              });
              document.querySelectorAll('.view').forEach((v) => {
                v.classList.toggle('active', v.id === 'view-' + currentView);
              });
            });
          });

          function flash(button, label) {
            const original = button.textContent;
            button.textContent = label;
            button.disabled = true;
            setTimeout(() => {
              button.textContent = original;
              button.disabled = false;
            }, 1200);
          }

          async function copyText(text, button) {
            try {
              await navigator.clipboard.writeText(text);
              flash(button, 'Copied!');
            } catch (error) {
              const area = document.createElement('textarea');
              area.value = text;
              area.style.position = 'fixed';
              area.style.opacity = '0';
              document.body.appendChild(area);
              area.select();
              const ok = document.execCommand('copy');
              document.body.removeChild(area);
              flash(button, ok ? 'Copied!' : 'Copy failed');
            }
          }

          document.getElementById('copy-content').addEventListener('click', (event) => {
            copyText(copyData.note, event.currentTarget);
          });

          function copySelection(holder) {
            const selection = window.getSelection();
            const previousRanges = Array.from({ length: selection.rangeCount }, (_, i) =>
              selection.getRangeAt(i).cloneRange());
            try {
              const range = document.createRange();
              range.selectNodeContents(holder);
              selection.removeAllRanges();
              selection.addRange(range);
              // An unselectable source copies nothing yet reports success.
              if (selection.isCollapsed) return false;
              return document.execCommand('copy');
            } catch (error) {
              return false;
            } finally {
              selection.removeAllRanges();
              previousRanges.forEach((range) => selection.addRange(range));
            }
          }

          async function copyRichText(html, plain, button, imageSource) {
            // Let the browser include image resources alongside the formatted text,
            // rather than copying local paths or separate, unordered image items.
            if (imageSource && copySelection(imageSource)) {
              flash(button, 'Copied!');
              return;
            }
            try {
              await navigator.clipboard.write([
                new ClipboardItem({
                  'text/html': new Blob([html], { type: 'text/html' }),
                  'text/plain': new Blob([plain], { type: 'text/plain' }),
                }),
              ]);
              flash(button, 'Copied!');
            } catch (error) {
              // Fall back to copying a rendered selection, which carries text/html too.
              const holder = imageSource || createCopySource(html);
              const ok = copySelection(holder);
              if (!imageSource) holder.remove();
              flash(button, ok ? 'Copied!' : 'Copy failed');
            }
          }

          document.getElementById('copy-html').addEventListener('click', (event) => {
            const button = event.currentTarget;
            const html = copyData[currentView + 'HTML'];
            const imageSource = currentView === 'note' && noteCopyImages.length ? noteCopySource : null;
            if (imageSource && !noteImagesReady) {
              flash(button, noteImagesFailed ? 'Image unavailable' : 'Images loading');
              return;
            }
            if (html) {
              copyRichText(html, copyData[currentView === 'note' ? 'transcript' : currentView], button, imageSource);
            } else {
              flash(button, 'Nothing to copy');
            }
          });

          document.getElementById('copy-md-path').addEventListener('click', (event) => {
            copyText(copyData.markdownReference, event.currentTarget);
          });
        </script>
      </body>
      </html>
      """
  }

  static func escape(_ text: String) -> String {
    text
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }

  /// A paragraph of rich-text-safe HTML. Email and chat editors (Gmail, Teams, Slack)
  /// drop `<style>` blocks and relative resources, so the markup is plain and unstyled.
  private static func paragraphHTML(_ text: String) -> String {
    "<p>\(escape(text).replacingOccurrences(of: "\n", with: "<br>"))</p>"
  }

  /// The note as a paste-friendly HTML fragment: the title heading, then each entry's
  /// text and embedded PNG in order. Data URLs carry the bytes across the clipboard without
  /// requiring the destination to read the export's local images directory.
  static func renderClipboardHTML(
    entries: [NoteEntry], startedAt: Date, title: String, screenshots: [String: Data] = [:]
  ) -> String {
    var parts = ["<h2>\(escape(title))</h2>"]
    for entry in entries {
      parts.append(paragraphHTML(entry.text))
      if let fileName = entry.screenshotFileName {
        if let data = screenshots[fileName], !data.isEmpty {
          parts.append(
            "<p><img src=\"data:image/png;base64,\(data.base64EncodedString())\" "
              + "alt=\"Screenshot\" style=\"max-width:100%;height:auto\"></p>"
          )
        } else {
          parts.append("<p><em>Screenshot unavailable</em></p>")
        }
      }
    }
    return parts.joined(separator: "\n")
  }

  /// A paste-friendly HTML fragment for free text such as the transcript or cleaned note.
  static func renderClipboardHTML(text: String) -> String {
    text.components(separatedBy: "\n\n")
      .map(paragraphHTML)
      .joined(separator: "\n")
  }

  /// JSON payload the page's copy buttons read from. The "note" view copies the
  /// markdown representation since it is the closest text equivalent of the note.
  /// The `*HTML` entries feed the Copy HTML button, which puts rich text on the clipboard.
  /// `<` is escaped so note content can never terminate the embedding script tag.
  private static func copyDataJSON(
    noteMarkdown: String,
    noteHTML: String,
    transcript: String,
    cleaned: String?,
    markdownReference: String
  ) -> String {
    var payload: [String: String] = [
      "note": noteMarkdown,
      "noteHTML": noteHTML,
      "transcript": transcript,
      "transcriptHTML": renderClipboardHTML(text: transcript),
      "markdownReference": markdownReference,
    ]
    if let cleaned {
      payload["cleaned"] = cleaned
      payload["cleanedHTML"] = renderClipboardHTML(text: cleaned)
    }
    guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    else {
      return "{}"
    }
    return String(decoding: data, as: UTF8.self)
      .replacingOccurrences(of: "<", with: "\\u003c")
  }
}
