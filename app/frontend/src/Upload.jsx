import { useState } from "react";

const ASSIGNMENT_ID = 1;

export default function Upload() {
  const [file, setFile] = useState(null);
  const [status, setStatus] = useState("");

  async function upload() {
    if (!file) return;
    setStatus("Uploading...");

    // 1. ask the API for a presigned POST
    const res = await fetch(`/api/assignments/${ASSIGNMENT_ID}/upload-url`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ filename: file.name }),
    });
    if (!res.ok) {
      setStatus("Could not get upload link");
      return;
    }
    const { url, fields, key } = await res.json();

    // 2. send the file straight to S3, the file field must be last
    const form = new FormData();
    Object.entries(fields).forEach(([name, value]) => form.append(name, value));
    form.append("file", file);

    const s3Res = await fetch(url, { method: "POST", body: form });
    setStatus(s3Res.ok ? "Uploaded: " + key : "Upload failed (max 50 MB)");
  }

  return (
    <div className="card">
      <h2>Assignment upload</h2>
      <input type="file" onChange={(e) => setFile(e.target.files[0])} />
      <button onClick={upload}>Upload</button>
      <p className="status">{status}</p>
    </div>
  );
}
