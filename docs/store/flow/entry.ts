import { createRenderSession } from '@ff/studio/export/renderSlide';

// Renders a hand-built project with the studio's own export code.
const session = createRenderSession();
const toBase64 = (blob: Blob) => new Promise<string>((resolve, reject) => {
  const reader = new FileReader();
  reader.onload = () => resolve(String(reader.result).split(',')[1]);
  reader.onerror = () => reject(reader.error);
  reader.readAsDataURL(blob);
});
(window as any).ffRender = async (project: any, slideIndex: number) => {
  const blob = await session.render({
    project, slide: project.slides[slideIndex], output: project.outputs[0], slideIndex,
    options: { format: 'png', scale: 1, quality: 0.92 },
  });
  return toBase64(blob);
};
(window as any).ffReady = true;
