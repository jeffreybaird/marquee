/**
 * SpacesUploader hook
 *
 * Used by: Admin forms that accept image uploads (series covers, season
 * covers, collection covers, custom video thumbnails, …).
 *
 * Direct-to-DigitalOcean-Spaces upload. Mirrors the MuxUploader flow:
 *   1. User picks a file via a file input inside this element.
 *   2. Hook asks the server for a presigned PUT URL.
 *   3. Hook PUTs the bytes directly to Spaces — bypassing our server.
 *   4. Hook reports progress / completion / error to the LiveView.
 *
 * The hook lives on a persistent wrapper (phx-update="ignore" is the
 * caller's job) so file references survive modal re-renders triggered
 * by the initial presign event.
 *
 * Dataset attributes (on the hook element):
 *   data-upload-kind — string identifier forwarded with every event,
 *                      e.g. "series_cover". The server uses this to
 *                      decide the bucket path.
 *   data-target-id   — optional, opaque caller-chosen id so the server
 *                      knows which field to update when one form holds
 *                      multiple upload slots.
 *
 * Events pushed to the server:
 *   "spaces_presign_requested" {kind, target_id, filename, content_type, size}
 *   "spaces_upload_progress"   {kind, target_id, percent}
 *   "spaces_upload_complete"   {kind, target_id, public_url, key}
 *   "spaces_upload_error"      {kind, target_id, error}
 *
 * Events received from the server:
 *   "spaces_presign_ready" {kind, target_id, presigned_url, public_url, key, headers}
 */
const SpacesUploader = {
  mounted(this: any) {
    this.pendingFile = null as File | null

    const kind = this.el.dataset.uploadKind || ""
    const targetId = this.el.dataset.targetId || null

    const fileInput = this.el.querySelector<HTMLInputElement>("input[type=file]")
    if (!fileInput) return

    fileInput.addEventListener("change", (event: Event) => {
      const input = event.target as HTMLInputElement
      const file = input.files?.[0]
      if (!file) return

      this.pendingFile = file

      this.pushEvent("spaces_presign_requested", {
        kind,
        target_id: targetId,
        filename: file.name,
        content_type: file.type || "application/octet-stream",
        size: file.size,
      })
    })

    this.handleEvent(
      "spaces_presign_ready",
      ({
        kind: readyKind,
        target_id: readyTargetId,
        presigned_url,
        public_url,
        key,
        headers,
      }: {
        kind: string
        target_id: string | null
        presigned_url: string
        public_url: string
        key: string
        headers: Record<string, string>
      }) => {
        if (readyKind !== kind || readyTargetId !== targetId) return

        const file = this.pendingFile
        if (!file) return
        this.pendingFile = null

        this.uploadToSpaces(presigned_url, file, headers || {})
          .then(() => {
            this.pushEvent("spaces_upload_complete", {
              kind,
              target_id: targetId,
              public_url,
              key,
            })
          })
          .catch((err: Error) => {
            this.pushEvent("spaces_upload_error", {
              kind,
              target_id: targetId,
              error: err.message || String(err),
            })
          })
      },
    )
  },

  uploadToSpaces(url: string, file: File, headers: Record<string, string>): Promise<void> {
    return new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest()
      this.currentXhr = xhr

      xhr.upload.addEventListener("progress", (e: ProgressEvent) => {
        if (!e.lengthComputable) return
        const percent = Math.round((e.loaded / e.total) * 100)
        this.pushEvent("spaces_upload_progress", {
          kind: this.el.dataset.uploadKind || "",
          target_id: this.el.dataset.targetId || null,
          percent,
        })
      })

      xhr.addEventListener("load", () => {
        if (xhr.status >= 200 && xhr.status < 300) {
          resolve()
        } else {
          reject(new Error(`Upload failed with status ${xhr.status}`))
        }
      })

      xhr.addEventListener("error", () => {
        reject(new Error("Network error during upload"))
      })

      xhr.open("PUT", url)
      for (const [name, value] of Object.entries(headers)) {
        try {
          xhr.setRequestHeader(name, value)
        } catch (e) {
          // Browsers block a handful of headers; ignore the ones we can't set.
        }
      }
      xhr.send(file)
    })
  },

  destroyed(this: any) {
    if (this.currentXhr) {
      this.currentXhr.abort()
    }
  },
}

export default SpacesUploader
