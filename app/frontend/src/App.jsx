import { useEffect, useRef, useState } from "react";
import Upload from "./Upload.jsx";

const EXAM_ID = 1;
const AUTOSAVE_MS = 30000; // 30 seconds

export default function App() {
  const [attempt, setAttempt] = useState(null);
  const [answers, setAnswers] = useState("");
  const [status, setStatus] = useState("");
  // the timer reads the latest answers from this ref
  const answersRef = useRef("");

  async function startExam() {
    const res = await fetch(`/api/exams/${EXAM_ID}/start`, { method: "POST" });
    if (!res.ok) {
      setStatus("Could not start exam");
      return;
    }
    setAttempt(await res.json());
  }

  // autosave every 30 s once the exam has started
  useEffect(() => {
    if (!attempt) return;

    async function save() {
      try {
        const res = await fetch(`/api/attempts/${attempt.attempt_id}/answers`, {
          method: "PUT",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ answers: answersRef.current }),
        });
        if (!res.ok) throw new Error();
        const data = await res.json();
        setStatus("Saved at " + new Date(data.saved_at).toLocaleTimeString());
      } catch {
        // answers stay in the textarea, the next autosave tries again
        setStatus("Save failed, will retry");
      }
    }

    const timer = setInterval(save, AUTOSAVE_MS);
    return () => clearInterval(timer);
  }, [attempt]);

  function onType(e) {
    setAnswers(e.target.value);
    answersRef.current = e.target.value;
  }

  return (
    <div className="page">
      <h1>Online Exam</h1>

      {!attempt && <button onClick={startExam}>Start exam</button>}

      {attempt && (
        <div className="card">
          <p>Attempt #{attempt.attempt_id}</p>
          <ol>
            {attempt.questions.map((q) => (
              <li key={q.id}>{q.text}</li>
            ))}
          </ol>
          <textarea rows="10" value={answers} onChange={onType} placeholder="Type your answers here" />
          <p className="status">{status || "Autosaves every 30 seconds"}</p>
        </div>
      )}

      <Upload />
      {!attempt && status && <p className="status">{status}</p>}
    </div>
  );
}
