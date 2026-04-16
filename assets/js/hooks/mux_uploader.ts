/**
 * MuxUploader hook
 *
 * Used by: Admin.ContentLive
 *
 * Handles direct video upload from browser to Mux.
 * Video bytes never touch Bobine's servers.
 *
 * This hook lives on a persistent element outside the upload modal.
 * It captures selected files when they change, so file references
 * survive the modal re-render that happens on form submit.
 *
 * Supports multi-file upload: files are uploaded sequentially.
 * Each file is assigned a client_id so the server can match
 * files to their Mux upload URLs.
 *
 * Events received from server:
 *   - "start_upload"       { upload_url: string, video_id: string }         (single file, legacy)
 *   - "start_multi_upload" { queue: [{ client_id, video_id, upload_url }] } (multi file)
 *
 * Events sent to server:
 *   - "files_selected"   { files: [{ client_id: string, name: string }] }
 *   - "upload_progress"  { video_id: string, percent: number }
 *   - "upload_complete"  { video_id: string }
 *   - "upload_error"     { video_id: string, error: string }
 */

const MuxUploader = {
  mounted() {
    this.clientIdCounter = 0
    this.selectedFiles = new Map<string, File>()

    // Listen for file selection anywhere in the document
    // (the file input is in the modal which may re-render)
    document.addEventListener("change", (e: Event) => {
      const target = e.target as HTMLInputElement
      if (target?.getAttribute("data-test") === "upload-file" && target.files?.length) {
        this.selectedFiles.clear()
        const fileEntries: { client_id: string; name: string }[] = []

        for (const file of Array.from(target.files)) {
          const clientId = `file_${++this.clientIdCounter}`
          this.selectedFiles.set(clientId, file)
          fileEntries.push({ client_id: clientId, name: file.name })
        }

        this.pushEvent("files_selected", { files: fileEntries })
      }
    })

    // Legacy single-file upload (kept for backwards compatibility)
    this.handleEvent("start_upload", ({ upload_url, video_id }: { upload_url: string; video_id: string }) => {
      const file = this.selectedFiles.values().next().value
      if (!file) {
        this.pushEvent("upload_error", { video_id, error: "No file selected" })
        return
      }

      this.uploadToMux(upload_url, file, video_id)
      this.selectedFiles.clear()
    })

    // Multi-file upload: receives a queue of { client_id, video_id, upload_url }
    this.handleEvent("start_multi_upload", ({ queue }: { queue: Array<{ client_id: string; video_id: string; upload_url: string }> }) => {
      this.uploadQueue(queue)
    })
  },

  async uploadQueue(queue: Array<{ client_id: string; video_id: string; upload_url: string }>) {
    for (const entry of queue) {
      const file = this.selectedFiles.get(entry.client_id)
      if (!file) {
        this.pushEvent("upload_error", {
          video_id: entry.video_id,
          error: "File no longer available",
        })
        continue
      }

      await this.uploadToMux(entry.upload_url, file, entry.video_id)
    }
    this.selectedFiles.clear()
  },

  uploadToMux(url: string, file: File, videoId: string): Promise<void> {
    return new Promise((resolve) => {
      try {
        const xhr = new XMLHttpRequest()
        this.currentXhr = xhr

        xhr.upload.addEventListener("progress", (e: ProgressEvent) => {
          if (e.lengthComputable) {
            const percent = Math.round((e.loaded / e.total) * 100)
            this.pushEvent("upload_progress", { video_id: videoId, percent })
          }
        })

        xhr.addEventListener("load", () => {
          if (xhr.status >= 200 && xhr.status < 300) {
            this.pushEvent("upload_complete", { video_id: videoId })
          } else {
            this.pushEvent("upload_error", {
              video_id: videoId,
              error: `Upload failed with status ${xhr.status}`,
            })
          }
          resolve()
        })

        xhr.addEventListener("error", () => {
          this.pushEvent("upload_error", {
            video_id: videoId,
            error: "Network error during upload",
          })
          resolve()
        })

        xhr.open("PUT", url)
        xhr.send(file)
      } catch (error) {
        this.pushEvent("upload_error", {
          video_id: videoId,
          error: String(error),
        })
        resolve()
      }
    })
  },

  destroyed() {
    if (this.currentXhr) {
      this.currentXhr.abort()
    }
  },
}

export default MuxUploader
