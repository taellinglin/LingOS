let currentMode = 'A';  // Default mode set to 'A'
let toggleButtons = document.querySelectorAll('#toggle button');
let messageInput = document.getElementById('inputArea');
let pinnedArea = document.getElementById('pinnedArea');
let messagesArea = document.getElementById('messagesArea');

// Toggle mode selection
toggleButtons.forEach(btn => {
  btn.addEventListener('click', () => {
    toggleButtons.forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    currentMode = btn.dataset.mode;
  });
});

// Handle message input
messageInput.addEventListener('keydown', e => {
  if (e.key === 'Enter') {
    if (e.shiftKey) {
      // Let Shift+Enter insert a newline
      return;
    } else {
      e.preventDefault();
      const msg = messageInput.value.trim();
      if (msg) {
        handleMessage(msg);  // Handle the message
        messageInput.value = '';  // Clear the input area
      }
    }
  }
});

// Handle the message and measure latency
function handleMessage(msg) {
  // Record the start time for latency calculation
  const start = performance.now();

  const div = document.createElement('div');
  div.className = 'message';  // Set the default class for message div

  // Create a message for the pinned area (Top of the screen)
  if (currentMode === 'A') {
    div.classList.add('left', 'red');
    div.textContent = msg;
    pinnedArea.appendChild(div);  // Append to pinned area
  } else if (currentMode === 'H') {
    div.classList.add('center', 'blue');
    div.textContent = msg;
    messagesArea.appendChild(div);  // Append to main message area
  } else if (currentMode === 'O') {
    // Measure the latency and calculate it in microseconds
    const endtime = performance.now();
    const latency = (endtime- start); // Convert ms to ns
    console.log(`Latency: ${latency} ns`);

    div.classList.add('right', 'white');
    div.textContent = msg + ` (Latency: ${latency} ms)`;  // Append latency to message
    messagesArea.appendChild(div);  // Append to main message area
  }

  // Optional: fade-in effect for message
  div.style.opacity = 0;
  div.style.transition = 'opacity 0.3s ease-in-out';
  requestAnimationFrame(() => (div.style.opacity = 1));
}
