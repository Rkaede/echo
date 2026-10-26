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

  /// The note as markdown: timestamped sections with embedded screenshot images.
  static func renderMarkdown(entries: [NoteEntry], startedAt: Date) -> String {
    let titleFormatter = DateFormatter()
    titleFormatter.dateStyle = .full
    titleFormatter.timeStyle = .short

    let timeFormatter = DateFormatter()
    timeFormatter.dateFormat = "h:mm:ss a"

    var lines = ["# Echo Note — \(titleFormatter.string(from: startedAt))", ""]
    for entry in entries {
      lines.append("## \(timeFormatter.string(from: entry.timestamp))")
      lines.append("")
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

    let timeFormatter = DateFormatter()
    timeFormatter.dateFormat = "h:mm:ss a"

    let entriesHTML = entries.map { entry -> String in
      var block = """
            <article class="entry">
              <div class="entry-time">\(escape(timeFormatter.string(from: entry.timestamp)))</div>
              <p class="entry-text">\(escape(entry.text))</p>
        """
      if let fileName = entry.screenshotFileName,
        let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
      {
        block += """

              <a href="images/\(encoded)" target="_blank">
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
        <style>
          :root {
            color-scheme: light dark;
            --bg: #f5f5f7;
            --card-bg: #ffffff;
            --text: #1d1d1f;
            --muted: #6e6e73;
            --accent: #0071e3;
            --border: rgba(0, 0, 0, 0.08);
          }
          @media (prefers-color-scheme: dark) {
            :root {
              --bg: #161617;
              --card-bg: #1f1f21;
              --text: #f5f5f7;
              --muted: #a1a1a6;
              --accent: #2997ff;
              --border: rgba(255, 255, 255, 0.1);
            }
          }
          * { box-sizing: border-box; }
          body {
            margin: 0;
            padding: 48px 24px 96px;
            background: var(--bg);
            color: var(--text);
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
            line-height: 1.55;
          }
          main { max-width: 760px; margin: 0 auto; }
          header { margin-bottom: 24px; }
          header h1 { font-size: 1.7rem; margin: 0 0 4px; letter-spacing: -0.02em; }
          header .change-title { font-size: 1.1rem; font-weight: 600; margin: 8px 0 4px; overflow-wrap: anywhere; }
          header .subtitle { color: var(--muted); font-size: 0.95rem; }
          .toolbar {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
            align-items: center;
            justify-content: space-between;
            margin-bottom: 24px;
          }
          .segmented {
            display: inline-flex;
            background: var(--card-bg);
            border: 1px solid var(--border);
            border-radius: 10px;
            padding: 3px;
            gap: 2px;
          }
          .seg-btn {
            border: none;
            background: transparent;
            color: var(--muted);
            font: inherit;
            font-size: 0.9rem;
            padding: 5px 14px;
            border-radius: 7px;
            cursor: pointer;
          }
          .seg-btn.active {
            background: var(--accent);
            color: #ffffff;
          }
          .toolbar-actions { display: inline-flex; gap: 8px; }
          .action-btn {
            border: 1px solid var(--border);
            background: var(--card-bg);
            color: var(--accent);
            font: inherit;
            font-size: 0.9rem;
            padding: 6px 14px;
            border-radius: 10px;
            cursor: pointer;
          }
          .action-btn:hover { border-color: var(--accent); }
          .action-btn:disabled { opacity: 0.7; cursor: default; }
          .view { display: none; }
          .view.active { display: block; }
          .entry {
            background: var(--card-bg);
            border: 1px solid var(--border);
            border-radius: 14px;
            padding: 20px 24px;
            margin-bottom: 20px;
            box-shadow: 0 1px 3px rgba(0, 0, 0, 0.06);
          }
          .entry-time {
            color: var(--muted);
            font-size: 0.8rem;
            font-variant-numeric: tabular-nums;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            margin-bottom: 8px;
          }
          .entry-text {
            margin: 0 0 12px;
            font-size: 1.05rem;
            white-space: pre-wrap;
          }
          .entry-text:last-child { margin-bottom: 0; }
          .entry-text.unavailable { color: var(--muted); font-style: italic; }
          .entry-screenshot {
            display: block;
            width: 100%;
            border-radius: 10px;
            border: 1px solid var(--border);
          }
          footer {
            color: var(--muted);
            font-size: 0.85rem;
            text-align: center;
            margin-top: 40px;
          }
        </style>
      </head>
      <body>
        <main>
          <header>
            <h1>Echo Note</h1>
            <div class="change-title">\(escape(title))</div>
            <div class="subtitle">\(escape(titleFormatter.string(from: startedAt))) · \(entries.count) \(entries.count == 1 ? "entry" : "entries")</div>
          </header>
          <div class="toolbar">
            <div class="segmented" role="tablist">
              <button class="seg-btn active" data-view="note">Note</button>
              <button class="seg-btn" data-view="transcript">Transcript</button>
              <button class="seg-btn" data-view="cleaned">Cleaned Up</button>
            </div>
            <div class="toolbar-actions">
              <button class="action-btn" id="copy-content" title="Copy the current view to the clipboard">Copy</button>
              <button class="action-btn" id="copy-html" title="Copy formatted text and, in Note view, screenshots to paste into email or chat apps">Copy HTML</button>
              <button class="action-btn" id="copy-md-path" title="Copy the change title and the path of the Markdown file saved next to this page">Copy Title + Path</button>
            </div>
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
          <footer>Created with Echo notes mode</footer>
        </main>
        <script id="copy-data" type="application/json">\(copyData)</script>
        <script>
          const copyData = JSON.parse(document.getElementById('copy-data').textContent);
          let currentView = 'note';

          // Preload embedded PNGs before the click so selection copying stays inside
          // the user gesture. Safari packages the loaded resources in a WebArchive:
          // https://webkit.org/blog/8170/clipboard-api-improvements/
          const noteCopySource = document.createElement('div');
          noteCopySource.innerHTML = copyData.noteHTML;
          noteCopySource.setAttribute('aria-hidden', 'true');
          noteCopySource.style.cssText = 'position:absolute;left:-10000px;top:0;width:760px';
          document.body.appendChild(noteCopySource);
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
            const button = event.currentTarget;
            const text = copyData[currentView];
            if (text) {
              copyText(text, button);
            } else {
              flash(button, 'Nothing to copy');
            }
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
              const holder = imageSource || document.createElement('div');
              if (!imageSource) {
                holder.innerHTML = html;
                holder.style.cssText = 'position:absolute;left:-10000px;top:0;width:760px';
                document.body.appendChild(holder);
              }
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

  /// The note as a paste-friendly HTML fragment: a heading per entry followed by its
  /// text and embedded PNG. Data URLs carry the bytes across the clipboard without
  /// requiring the destination to read the export's local images directory.
  static func renderClipboardHTML(
    entries: [NoteEntry], startedAt: Date, title: String, screenshots: [String: Data] = [:]
  ) -> String {
    let timeFormatter = DateFormatter()
    timeFormatter.dateFormat = "h:mm:ss a"

    var parts = ["<h2>\(escape(title))</h2>"]
    for entry in entries {
      parts.append("<h3>\(escape(timeFormatter.string(from: entry.timestamp)))</h3>")
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
