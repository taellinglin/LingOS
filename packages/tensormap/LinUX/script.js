const canvas = document.getElementById("gameCanvas");
const ctx = canvas.getContext("2d");

const SCREEN_WIDTH = 1920;
const SCREEN_HEIGHT = 1080;
const FONT_SIZE = 10;
const CELL_SIZE = 10;
const FPS = 32;
const RED = "rgb(255, 0, 0)";
const BLUE = "rgb(0, 0, 255)";
const BLACK = "rgb(0, 0, 0)";

canvas.width = SCREEN_WIDTH;
canvas.height = SCREEN_HEIGHT;

const cols = Math.floor(SCREEN_WIDTH / CELL_SIZE);
const rows = Math.floor(SCREEN_HEIGHT / CELL_SIZE);
const halfCols = Math.floor(cols / 2);
const halfRows = Math.floor(rows / 2);

// Random letter generator
function randomChar() {
  const letters = "abcdefghijklmnopqrstuvwxyz";
  return letters[Math.floor(Math.random() * letters.length)];
}

// Random color generator (Red or Blue)
function randomColor() {
  return Math.random() > 0.5 ? RED : BLUE;
}

// Initialize the grid with random values
function randomCell() {
  return {
    char: randomChar(),
    color: randomColor(),
    alive: Math.random() > 0.5,
  };
}

let quarterGrid = Array.from({ length: halfRows }, () =>
  Array.from({ length: halfCols }, randomCell)
);

// Create the full grid based on 4-corner symmetry
function buildFullGrid() {
  const grid = [];
  for (let y = 0; y < rows; y++) {
    const row = [];
    for (let x = 0; x < cols; x++) {
      const sourceX = x < halfCols ? x : cols - x - 1;
      const sourceY = y < halfRows ? y : rows - y - 1;
      row.push({ ...quarterGrid[sourceY][sourceX] });
    }
    grid.push(row);
  }
  return grid;
}

let grid = buildFullGrid();

// Count alive neighbors for each cell
function countAliveNeighbors(x, y) {
  let count = 0;
  for (let dy = -1; dy <= 1; dy++) {
    for (let dx = -1; dx <= 1; dx++) {
      if (dx === 0 && dy === 0) continue;
      const nx = (x + dx + cols) % cols;
      const ny = (y + dy + rows) % rows;
      if (grid[ny][nx].alive) count++;
    }
  }
  return count;
}

// Update the quarter grid based on the rules
function updateQuarterGrid() {
  const newQuarter = quarterGrid.map(row => row.map(cell => ({ ...cell })));

  for (let y = 0; y < halfRows; y++) {
    for (let x = 0; x < halfCols; x++) {
      const cell = quarterGrid[y][x];
      const fullX = x;
      const fullY = y;
      const neighbors = countAliveNeighbors(fullX, fullY);

      if (cell.alive) {
        if (neighbors < 2 || neighbors > 3) {
          newQuarter[y][x].alive = false;
        }
      } else {
        if (neighbors === 3) {
          newQuarter[y][x].alive = true;
          newQuarter[y][x].char = randomChar();
          newQuarter[y][x].color = randomColor();
        }
      }

      // Perpetual nudge
      if (Math.random() < 0.0005) {
        newQuarter[y][x].alive = !newQuarter[y][x].alive;
      }
    }
  }

  quarterGrid = newQuarter;
}

// Draw the grid on the canvas
function drawGrid() {
  grid = buildFullGrid();
  ctx.fillStyle = BLACK;
  ctx.fillRect(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT);

  for (let y = 0; y < rows; y++) {
    for (let x = 0; x < cols; x++) {
      const cell = grid[y][x];
      if (cell.alive) {
        ctx.font = `${FONT_SIZE}px o`;
        ctx.fillStyle = cell.color;
        ctx.fillText(cell.char, x * CELL_SIZE, y * CELL_SIZE + FONT_SIZE);
      }
    }
  }
}

// Main game loop
function gameLoop() {
  updateQuarterGrid();
  drawGrid();
}

// Update at FPS
setInterval(gameLoop, 1000 / FPS);
