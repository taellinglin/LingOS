const SCREEN_WIDTH = window.innerWidth;
const SCREEN_HEIGHT = window.innerHeight;
const FONT_SIZE = 11;
const CELL_SIZE = 11;
const FPS = 32;

const RED = 'rgb(255, 0, 0)';
const BLUE = 'rgb(0, 0, 255)';
const COLORS = [RED, BLUE];

const canvas = document.getElementById("lifeCanvas");
canvas.width = SCREEN_WIDTH;
canvas.height = SCREEN_HEIGHT;
const ctx = canvas.getContext("2d");

const cols = Math.floor(SCREEN_WIDTH / CELL_SIZE);
const rows = Math.floor(SCREEN_HEIGHT / CELL_SIZE);
const half_cols = Math.floor(cols / 2);
const half_rows = Math.floor(rows / 2);

// Generate a random character cell
function randomCell() {
  return {
    char: String.fromCharCode(97 + Math.floor(Math.random() * 26)), // a-z
    color: COLORS[Math.floor(Math.random() * COLORS.length)],
    alive: Math.random() < 0.5
  };
}

// Initialize 1/4 grid
let quarterGrid = Array.from({ length: half_rows }, () =>
  Array.from({ length: half_cols }, () => randomCell())
);

// Build full 4-way symmetric grid
function buildFullGrid() {
  const grid = Array.from({ length: rows }, (_, y) =>
    Array.from({ length: cols }, (_, x) => {
      const sourceX = x < half_cols ? x : cols - x - 1;
      const sourceY = y < half_rows ? y : rows - y - 1;
      return { ...quarterGrid[sourceY][sourceX] };
    })
  );
  return grid;
}

let fullGrid = buildFullGrid();

function countAliveNeighbors(x, y) {
  let count = 0;
  for (let dy = -1; dy <= 1; dy++) {
    for (let dx = -1; dx <= 1; dx++) {
      if (dx === 0 && dy === 0) continue;
      const nx = (x + dx + cols) % cols;
      const ny = (y + dy + rows) % rows;
      if (fullGrid[ny][nx].alive) count++;
    }
  }
  return count;
}

function updateQuarterGrid() {
  const newQuarter = quarterGrid.map(row => row.map(cell => ({ ...cell })));

  for (let y = 0; y < half_rows; y++) {
    for (let x = 0; x < half_cols; x++) {
      const cell = quarterGrid[y][x];
      const neighbors = countAliveNeighbors(x, y);

      if (cell.alive) {
        if (neighbors < 2 || neighbors > 3) {
          newQuarter[y][x].alive = false;
        }
      } else {
        if (neighbors === 3) {
          newQuarter[y][x].alive = true;
          newQuarter[y][x].char = String.fromCharCode(97 + Math.floor(Math.random() * 26));
          newQuarter[y][x].color = COLORS[Math.floor(Math.random() * COLORS.length)];
        }
      }

      if (Math.random() < 0.0005) {
        newQuarter[y][x].alive = !newQuarter[y][x].alive;
      }
    }
  }

  quarterGrid = newQuarter;
}

function drawGrid() {
  fullGrid = buildFullGrid();
  ctx.clearRect(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT);

  for (let y = 0; y < rows; y++) {
    for (let x = 0; x < cols; x++) {
      const cell = fullGrid[y][x];
      if (cell.alive) {
        ctx.fillStyle = cell.color;
        ctx.fillText(cell.char, x * CELL_SIZE, y * CELL_SIZE);
      }
    }
  }
}

// Animation loop
function loop() {
  updateQuarterGrid();
  drawGrid();
  setTimeout(() => requestAnimationFrame(loop), 1000 / FPS);
}

// Load font using FontFace API (absolute path from web root)
const daemonFont = new FontFace("Daemon", "url('/7075.otf')");

daemonFont.load().then(function (loadedFont) {
  document.fonts.add(loadedFont);
  ctx.font = `${FONT_SIZE}px Daemon`;
  loop(); // Start loop after font is loaded
});
